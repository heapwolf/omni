// src/keychain/android/play-integrity/OmniAttest.java
package com.omni;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

import com.google.android.gms.tasks.Tasks;
import com.google.android.play.core.integrity.IntegrityManagerFactory;
import com.google.android.play.core.integrity.StandardIntegrityManager;
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest;
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityToken;
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider;
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest;

import java.util.concurrent.TimeUnit;

/// OmniKeychain's Play Integrity: a standard request's token, for the
/// server to decode with Google. Built in only when omni.json turns on
/// playIntegrity; the classes it uses are vendor/play-integrity's jar, and
/// nothing else in the app calls them.
///
/// Any failure, including a missing class or no Play Store, is a null token.
/// Blocking: called off the main thread.
public final class OmniAttest {
    /// Where omni writes omni.json's cloud project number, as "project:<n>": a
    /// bare number would be read as an int or a float, and lose digits.
    static final String PROJECT = "omni.play_integrity.cloud_project";
    static final String PREFIX = "project:";
    static final long TIMEOUT_SECONDS = 20;

    private static StandardIntegrityTokenProvider provider;

    private OmniAttest() {}

    /// A token whose request hash is `requestHash`, or null.
    public static synchronized String token(Context context, String requestHash) {
        try {
            if (provider == null) {
                long project = cloudProject(context);
                if (project <= 0) return null;
                StandardIntegrityManager manager = IntegrityManagerFactory.createStandard(context.getApplicationContext());
                provider = Tasks.await(manager.prepareIntegrityToken(
                        PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build()),
                        TIMEOUT_SECONDS, TimeUnit.SECONDS);
            }
            StandardIntegrityToken token = Tasks.await(provider.request(
                    StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build()),
                    TIMEOUT_SECONDS, TimeUnit.SECONDS);
            return token.token();
        } catch (Throwable error) {
            // A provider can expire; the next call prepares a new one.
            provider = null;
            return null;
        }
    }

    static long cloudProject(Context context) throws PackageManager.NameNotFoundException {
        ApplicationInfo info = context.getPackageManager()
                .getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
        if (info.metaData == null) return 0;
        String value = info.metaData.getString(PROJECT);
        if (value == null || !value.startsWith(PREFIX)) return 0;
        try { return Long.parseLong(value.substring(PREFIX.length())); } catch (NumberFormatException e) { return 0; }
    }
}
