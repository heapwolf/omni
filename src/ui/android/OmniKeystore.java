// src/ui/android/OmniKeystore.java
package com.omni;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/// Not androidx.security: a Gradle dependency this build cannot resolve.
public final class OmniKeystore {
    private static final String PROVIDER = "AndroidKeyStore";
    private static final String PREFS = "omni.keychain";
    private static final String TRANSFORM = "AES/GCM/NoPadding";
    private static final int GCM_TAG_BITS = 128;
    private static final byte FORMAT_VERSION = 1;

    private OmniKeystore() {}

    // Accessibility levels, matching Swift's enum by ordinal. One Keystore key
    // per level: the restriction is a property of the key, not the value.
    private static String aliasFor(int level) {
        switch (level) {
            case 1:  return "omni.keychain.afterFirstUnlock";
            case 2:  return "omni.keychain.whenUnlockedThisDeviceOnly";
            case 3:  return "omni.keychain.afterFirstUnlockThisDeviceOnly";
            default: return "omni.keychain.whenUnlocked";
        }
    }

    /// Readable while the device is locked: no unlocked-device restriction.
    private static boolean afterFirstUnlock(int level) {
        return level == 1 || level == 3;
    }

    /// afterFirstUnlockThisDeviceOnly's values live in the no-backup
    /// directory, which Auto Backup never copies. (The Keystore key never
    /// leaves the device either way; this keeps a restored phone from holding
    /// a value it can't decrypt.) The other levels stay where they always were.
    private static File deviceOnly(Context context, String key) throws Exception {
        File directory = new File(context.getNoBackupFilesDir(), PREFS);
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("no directory");
        // Hashed, so a key is never a path.
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8));
        StringBuilder name = new StringBuilder();
        for (byte b : digest) name.append(String.format("%02x", b));
        return new File(directory, name.toString());
    }

    private static String readDeviceOnly(Context context, String key) throws Exception {
        File file = deviceOnly(context, key);
        if (!file.isFile()) return null;
        byte[] bytes = new byte[(int) file.length()];
        try (FileInputStream in = new FileInputStream(file)) {
            int read = 0;
            while (read < bytes.length) {
                int n = in.read(bytes, read, bytes.length - read);
                if (n < 0) break;
                read += n;
            }
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    /// Written whole, then renamed over the old: a crash leaves one or the other.
    private static void writeDeviceOnly(Context context, String key, String value) throws Exception {
        File file = deviceOnly(context, key);
        File temporary = new File(file.getPath() + ".tmp");
        try (FileOutputStream out = new FileOutputStream(temporary)) {
            out.write(value.getBytes(StandardCharsets.UTF_8));
            out.getFD().sync();
        }
        if (!temporary.renameTo(file)) throw new IllegalStateException("rename failed");
    }

    private static synchronized SecretKey keyFor(int level) throws Exception {
        String alias = aliasFor(level);
        KeyStore store = KeyStore.getInstance(PROVIDER);
        store.load(null);

        KeyStore.Entry existing = store.getEntry(alias, null);
        if (existing instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) existing).getSecretKey();
        }

        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER);
        KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(
                alias, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256);

        if (!afterFirstUnlock(level) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setUnlockedDeviceRequired(true);
        }

        generator.init(spec.build());
        return generator.generateKey();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /// Returns true on success. Stores version + level + iv + ciphertext, so a
    /// read knows which key to use without being told.
    public static boolean set(Context context, String key, byte[] value, int level) {
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORM);
            cipher.init(Cipher.ENCRYPT_MODE, keyFor(level));
            byte[] iv = cipher.getIV();
            byte[] ciphertext = cipher.doFinal(value);

            ByteArrayOutputStream out = new ByteArrayOutputStream();
            out.write(FORMAT_VERSION);
            out.write((byte) level);
            out.write((byte) iv.length);
            out.write(iv);
            out.write(ciphertext);

            String encoded = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
            // One place per key: a write at one level removes it from the other.
            if (level == 3) {
                writeDeviceOnly(context, key, encoded);
                prefs(context).edit().remove(key).apply();
            } else {
                prefs(context).edit().putString(key, encoded).apply();
                deviceOnly(context, key).delete();
            }
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /// Returns the plaintext, or null when the key is absent. Absence and
    /// failure are distinguished by the caller via `has`.
    public static byte[] get(Context context, String key) {
        try {
            String stored = prefs(context).getString(key, null);
            if (stored == null) stored = readDeviceOnly(context, key);
            if (stored == null) return null;

            byte[] blob = Base64.decode(stored, Base64.NO_WRAP);
            if (blob.length < 3 || blob[0] != FORMAT_VERSION) return null;

            int level = blob[1];
            int ivLength = blob[2];
            if (blob.length < 3 + ivLength) return null;

            byte[] iv = Arrays.copyOfRange(blob, 3, 3 + ivLength);
            byte[] ciphertext = Arrays.copyOfRange(blob, 3 + ivLength, blob.length);

            Cipher cipher = Cipher.getInstance(TRANSFORM);
            cipher.init(Cipher.DECRYPT_MODE, keyFor(level), new GCMParameterSpec(GCM_TAG_BITS, iv));
            return cipher.doFinal(ciphertext);
        } catch (Throwable t) {
            return null;
        }
    }

    public static boolean has(Context context, String key) {
        try {
            return prefs(context).contains(key) || deviceOnly(context, key).isFile();
        } catch (Throwable t) {
            return false;
        }
    }

    /// Returns true if something was removed.
    public static boolean delete(Context context, String key) {
        try {
            SharedPreferences preferences = prefs(context);
            boolean inPrefs = preferences.contains(key);
            if (inPrefs) preferences.edit().remove(key).apply();
            boolean inFile = deviceOnly(context, key).delete();
            return inPrefs || inFile;
        } catch (Throwable t) {
            return false;
        }
    }
}
