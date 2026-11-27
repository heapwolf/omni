// src/ui/android/OmniPush.java
package com.omni;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Message;
import android.os.Messenger;
import android.util.Base64;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/// OmniPush on Android: Google Play services' push, with no Google library. Platform APIs only:
///
/// 1. An installation, by REST: Firebase Installations' API (firebaseinstallations.googleapis.com),
///    which Play services needs to issue a token. Its id and refresh token stay in this app's own
///    preferences.
/// 2. The token, from Play services on the device: a bound service and a Messenger, as Google's
///    own messaging library asks (com.google.android.gms.cloudmessaging.Rpc, with the fields of
///    com.google.firebase.messaging.GmsRpc). Not a published interface; a failure is "unavailable".
/// 3. Delivery: Receiver, which only Play services can reach (the manifest's
///    com.google.android.c2dm.permission.SEND, a permission only it holds). The server sends data
///    only, a title and a body, so Play services never shows anything itself: Receiver shows it,
///    and a tap opens the app.
///
/// The project's ids come from omni.json's `push`, as manifest meta-data. Without them, or without
/// Play services, there's no token, and nothing else changes.
public final class OmniPush {
    static final int PERMISSION_REQUEST = 41101;
    static final String PROJECT = "omni.push.project_id";
    static final String APP = "omni.push.app_id";
    static final String KEY = "omni.push.api_key";
    /// "sender:<number>": a bare number would be read as an int or a float, and lose digits.
    static final String SENDER = "omni.push.sender";
    static final String CHANNEL_NAME = "omni.push.channel";
    static final String CHANNEL = "omni.push";
    static final String PREFERENCES = "omni.push";
    static final String GMS = "com.google.android.gms";
    static final String POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS";
    /// What Google's library reports itself as; Play services reads these.
    static final String INSTALLATIONS_SDK = "a:18.0.0";
    static final String MESSAGING_CLIENT = "fcm-26.0.2";
    static final long WAIT_SECONDS = 30;

    private static volatile CountDownLatch permissionAnswer;
    private static volatile boolean permissionGranted;
    private static int nextRequest = 1;

    private OmniPush() {}

    /// "token:<token>", "denied", "not-asked", or "unavailable:<why>". Blocking: called off the
    /// main thread (JNIBridge.c's omni_jni_push_token).
    public static synchronized String token(Activity activity, boolean prompting) {
        try {
            Context context = activity.getApplicationContext();
            Config config = Config.read(context);
            if (config == null) return "unavailable:no push in omni.json";
            String refused = permission(activity, prompting);
            if (refused != null) return refused;
            PackageInfo gms;
            try { gms = context.getPackageManager().getPackageInfo(GMS, 0); }
            catch (PackageManager.NameNotFoundException e) { return "unavailable:no Google Play services"; }
            // Older Play services take another, older request; omni asks only this one.
            if (gms.getLongVersionCode() < 12000000) return "unavailable:Google Play services too old";
            String[] installation = installation(context, config);
            return "token:" + register(context, config, gms, installation[0], installation[1]);
        } catch (Throwable error) {
            return "unavailable:" + error.getClass().getSimpleName() + ": " + error.getMessage();
        }
    }

    // MARK: Permission

    /// null when notifications can show; else "denied" or "not-asked".
    private static String permission(Activity activity, boolean prompting) throws InterruptedException {
        SharedPreferences preferences = activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
        if (Build.VERSION.SDK_INT >= 33
                && activity.checkSelfPermission(POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (!prompting) return preferences.getBoolean("asked", false) ? "denied" : "not-asked";
            preferences.edit().putBoolean("asked", true).apply();
            CountDownLatch answer = new CountDownLatch(1);
            permissionGranted = false;
            permissionAnswer = answer;
            activity.runOnUiThread(() -> activity.requestPermissions(new String[] { POST_NOTIFICATIONS }, PERMISSION_REQUEST));
            // The customer's to answer: as long as they take.
            answer.await();
            if (!permissionGranted) return "denied";
        }
        NotificationManager manager = activity.getSystemService(NotificationManager.class);
        return manager != null && manager.areNotificationsEnabled() ? null : "denied";
    }

    /// From OmniEventBridge.onRequestPermissionsResult, for PERMISSION_REQUEST.
    static void permissionResult(boolean granted) {
        permissionGranted = granted;
        CountDownLatch answer = permissionAnswer;
        if (answer != null) answer.countDown();
    }

    // MARK: Installation

    /// {id, auth token}: the installation kept, with a fresh auth token, or a new one.
    private static String[] installation(Context context, Config config) throws Exception {
        SharedPreferences preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
        String base = "https://firebaseinstallations.googleapis.com/v1/projects/" + config.project + "/installations";
        String id = preferences.getString("id", null), refresh = preferences.getString("refresh", null);
        if (id != null && refresh != null) {
            JSONObject ask = new JSONObject().put("installation",
                    new JSONObject().put("sdkVersion", INSTALLATIONS_SDK).put("appId", config.app));
            Answer answer = post(context, config, base + "/" + id + "/authTokens:generate", ask, "FIS_v2 " + refresh);
            if (answer.ok()) return new String[] { id, answer.json.getString("token") };
            // Gone (deleted, or the app's data cleared on the server's side): a new one, below.
            if (answer.status != 401 && answer.status != 404) throw new IOException("installations answered " + answer.status);
        }
        JSONObject ask = new JSONObject().put("fid", newID()).put("appId", config.app)
                .put("authVersion", "FIS_v2").put("sdkVersion", INSTALLATIONS_SDK);
        Answer answer = post(context, config, base, ask, null);
        if (!answer.ok()) throw new IOException("installations answered " + answer.status);
        id = answer.json.getString("fid");
        preferences.edit().putString("id", id).putString("refresh", answer.json.getString("refreshToken")).apply();
        return new String[] { id, answer.json.getJSONObject("authToken").getString("token") };
    }

    /// An installation id: 22 characters of base64url, its first four bits 0111.
    private static String newID() {
        byte[] bytes = new byte[17];
        new SecureRandom().nextBytes(bytes);
        bytes[0] = (byte) (0x70 | (bytes[0] & 0x0F));
        return Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING).substring(0, 22);
    }

    private static final class Answer {
        final int status;
        final JSONObject json;
        Answer(int status, JSONObject json) { this.status = status; this.json = json; }
        boolean ok() { return status >= 200 && status < 300 && json != null; }
    }

    /// The API key is restricted to this app, by its package and signing certificate: both go.
    private static Answer post(Context context, Config config, String url, JSONObject body, String authorization)
            throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setRequestMethod("POST");
            connection.setConnectTimeout((int) TimeUnit.SECONDS.toMillis(WAIT_SECONDS));
            connection.setReadTimeout((int) TimeUnit.SECONDS.toMillis(WAIT_SECONDS));
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("x-goog-api-key", config.key);
            connection.setRequestProperty("X-Android-Package", context.getPackageName());
            connection.setRequestProperty("X-Android-Cert", certificate(context));
            if (authorization != null) connection.setRequestProperty("Authorization", authorization);
            try (OutputStream out = connection.getOutputStream()) {
                out.write(body.toString().getBytes(StandardCharsets.UTF_8));
            }
            int status = connection.getResponseCode();
            InputStream stream = status < 400 ? connection.getInputStream() : connection.getErrorStream();
            JSONObject json = null;
            if (stream != null) {
                try (InputStream in = stream) {
                    ByteArrayOutputStream read = new ByteArrayOutputStream();
                    byte[] buffer = new byte[4096];
                    for (int n; (n = in.read(buffer)) > 0; ) read.write(buffer, 0, n);
                    String text = read.toString("UTF-8");
                    if (status < 400 && !text.isEmpty()) json = new JSONObject(text);
                }
            }
            return new Answer(status, json);
        } finally {
            connection.disconnect();
        }
    }

    /// The signing certificate's SHA-1, in upper-case hex: how Google's API keys name an Android app.
    private static String certificate(Context context) throws Exception {
        PackageInfo info = context.getPackageManager()
                .getPackageInfo(context.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
        byte[] digest = MessageDigest.getInstance("SHA-1")
                .digest(info.signingInfo.getApkContentsSigners()[0].toByteArray());
        StringBuilder hex = new StringBuilder();
        for (byte b : digest) hex.append(String.format("%02X", b));
        return hex.toString();
    }

    // MARK: Token

    /// The token Play services issues for this installation: what the server sends to.
    private static String register(Context context, Config config, PackageInfo gms, String id, String auth) throws Exception {
        PackageInfo app = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
        Bundle data = new Bundle();
        data.putString("scope", "*");
        data.putString("sender", config.sender);
        data.putString("subtype", config.sender);
        data.putString("gmp_app_id", config.app);
        data.putString("gmsv", Long.toString(gms.getLongVersionCode()));
        data.putString("osv", Integer.toString(Build.VERSION.SDK_INT));
        data.putString("app_ver", Long.toString(app.getLongVersionCode()));
        data.putString("app_ver_name", app.versionName == null ? "" : app.versionName);
        data.putString("firebase-app-name-hash", Base64.encodeToString(
                MessageDigest.getInstance("SHA-1").digest("[DEFAULT]".getBytes(StandardCharsets.UTF_8)),
                Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING));
        data.putString("Goog-Api-Key", config.key);
        data.putString("Goog-Firebase-Installations-Auth", auth);
        data.putString("appid", id);
        data.putString("cliv", MESSAGING_CLIENT);
        Bundle answer = ask(context, data);
        String token = answer.getString("registration_id");
        if (token != null && !token.isEmpty()) return token;
        throw new IOException("Play services refused: " + answer.getString("error"));
    }

    /// One request to Play services' messaging service, and its answer: bound, sent, unbound.
    private static Bundle ask(Context context, Bundle data) throws Exception {
        final int request = nextRequest++;
        final BlockingQueue<Bundle> answers = new ArrayBlockingQueue<>(1);
        final BlockingQueue<IBinder> bound = new ArrayBlockingQueue<>(1);
        HandlerThread thread = new HandlerThread("omni-push");
        thread.start();
        ServiceConnection connection = new ServiceConnection() {
            @Override public void onServiceConnected(ComponentName name, IBinder binder) { bound.offer(binder); }
            @Override public void onServiceDisconnected(ComponentName name) {}
        };
        try {
            Messenger replies = new Messenger(new Handler(thread.getLooper(), message -> {
                if (message.arg1 != request) return true;
                Bundle envelope = message.getData();
                Bundle result = envelope == null || envelope.getBoolean("unsupported", false) ? null : envelope.getBundle("data");
                if (result == null) {
                    result = new Bundle();
                    result.putString("error", "unsupported");
                }
                answers.offer(result);
                return true;
            }));
            Intent service = new Intent("com.google.android.c2dm.intent.REGISTER").setPackage(GMS);
            if (!context.bindService(service, connection, Context.BIND_AUTO_CREATE)) {
                throw new IOException("Play services' messaging can't be bound");
            }
            try {
                IBinder binder = bound.poll(WAIT_SECONDS, TimeUnit.SECONDS);
                if (binder == null) throw new IOException("Play services didn't connect");
                String descriptor = binder.getInterfaceDescriptor();
                if (!"android.os.IMessenger".equals(descriptor)) throw new IOException("Play services' messenger is " + descriptor);
                Message message = Message.obtain();
                message.what = 1;
                message.arg1 = request;
                message.replyTo = replies;
                Bundle envelope = new Bundle();
                envelope.putBoolean("oneWay", false);
                envelope.putString("pkg", context.getPackageName());
                envelope.putBundle("data", data);
                message.setData(envelope);
                new Messenger(binder).send(message);
                Bundle answer = answers.poll(WAIT_SECONDS, TimeUnit.SECONDS);
                if (answer == null) throw new IOException("Play services didn't answer");
                return answer;
            } finally {
                context.unbindService(connection);
            }
        } finally {
            thread.quitSafely();
        }
    }

    // MARK: Delivery

    /// Play services' delivery. Data only, from the app's server: a title and a body, shown here.
    public static final class Receiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            if ("com.google.android.c2dm.intent.RECEIVE".equals(intent.getAction())) {
                Bundle extras = intent.getExtras();
                // Only a message has words: "deleted_messages" and the like don't.
                String type = extras == null ? null : extras.getString("message_type");
                if (extras != null && (type == null || "gcm".equals(type))) {
                    String title = extras.getString("title"), body = extras.getString("body");
                    if (title != null || body != null) show(context, title, body, extras.getString("google.message_id"));
                }
            }
            if (isOrderedBroadcast()) setResultCode(Activity.RESULT_OK);
        }
    }

    /// A notification that opens the app.
    static void show(Context context, String title, String body, String id) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null || !manager.areNotificationsEnabled()) return;
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL, channelName(context),
                    NotificationManager.IMPORTANCE_HIGH));
        }
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent tap = open == null ? null
                : PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(context.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(tap)
                .build();
        manager.notify(id != null ? id.hashCode() : (int) System.currentTimeMillis(), notification);
    }

    private static String channelName(Context context) {
        try {
            ApplicationInfo info = context.getPackageManager()
                    .getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
            String name = info.metaData == null ? null : info.metaData.getString(CHANNEL_NAME);
            return name == null || name.isEmpty() ? "Notifications" : name;
        } catch (PackageManager.NameNotFoundException e) {
            return "Notifications";
        }
    }

    // MARK: Configuration

    /// omni.json's `push`, as the manifest's meta-data; null when it has none.
    static final class Config {
        final String project, app, key, sender;

        private Config(String project, String app, String key, String sender) {
            this.project = project; this.app = app; this.key = key; this.sender = sender;
        }

        static Config read(Context context) throws PackageManager.NameNotFoundException {
            ApplicationInfo info = context.getPackageManager()
                    .getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
            Bundle meta = info.metaData;
            if (meta == null) return null;
            String project = meta.getString(PROJECT), app = meta.getString(APP), key = meta.getString(KEY);
            String sender = meta.getString(SENDER);
            if (project == null || app == null || key == null || sender == null || !sender.startsWith("sender:")) return null;
            return new Config(project, app, key, sender.substring("sender:".length()));
        }
    }
}
