// src/ui/android/OmniApprovalKey.java
package com.omni;

import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.CancellationSignal;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;

import java.math.BigInteger;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;

/// OmniKeychain's approval keys: P-256 signing keys in the Android Keystore that need the
/// phone's strong (Class 3) biometric for every signature, and are invalidated when one is
/// enrolled. The prompt is the platform's BiometricPrompt (API 28, omni's minimum), so no
/// androidx. `sign` waits for the person: never call it on the main thread.
public final class OmniApprovalKey {
    private static final String PROVIDER = "AndroidKeyStore";
    private static final String PREFIX = "omni.approvalkey.";

    /// How the last `sign` ended, for the caller: 0 signed, 1 cancelled, 2 invalidated,
    /// 3 not found, 4 failed.
    public static volatile int lastStatus = 0;

    private OmniApprovalKey() {}

    /// 1 when a strong biometric is enrolled and usable, else 0.
    @SuppressWarnings("deprecation")
    public static int biometry(Context context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                BiometricManager manager = context.getSystemService(BiometricManager.class);
                return manager != null && manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                        == BiometricManager.BIOMETRIC_SUCCESS ? 1 : 0;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                BiometricManager manager = context.getSystemService(BiometricManager.class);
                return manager != null && manager.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS ? 1 : 0;
            }
            // API 28: fingerprints are the only strong biometric BiometricPrompt offers.
            if (!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) return 0;
            android.hardware.fingerprint.FingerprintManager fingerprints =
                    context.getSystemService(android.hardware.fingerprint.FingerprintManager.class);
            return fingerprints != null && fingerprints.isHardwareDetected() && fingerprints.hasEnrolledFingerprints() ? 1 : 0;
        } catch (Throwable t) {
            return 0;
        }
    }

    public static boolean has(Context context, String tag) {
        try {
            KeyStore store = KeyStore.getInstance(PROVIDER);
            store.load(null);
            return store.containsAlias(PREFIX + tag);
        } catch (Throwable t) {
            return false;
        }
    }

    /// A new key under `tag`, replacing any; its public half, x9.63 uncompressed (65 bytes).
    /// Null on failure.
    public static synchronized byte[] create(Context context, String tag) {
        try {
            String alias = PREFIX + tag;
            KeyStore store = KeyStore.getInstance(PROVIDER);
            store.load(null);
            if (store.containsAlias(alias)) store.deleteEntry(alias);

            KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Every use, strong biometric only: never the screen lock's PIN.
                spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG);
            }
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER);
            generator.initialize(spec.build());
            generator.generateKeyPair();

            ECPublicKey key = (ECPublicKey) store.getCertificate(alias).getPublicKey();
            byte[] out = new byte[65];
            out[0] = 0x04;
            put(key.getW().getAffineX(), out, 1);
            put(key.getW().getAffineY(), out, 33);
            return out;
        } catch (Throwable t) {
            return null;
        }
    }

    private static void put(BigInteger coordinate, byte[] out, int offset) {
        byte[] bytes = coordinate.toByteArray();
        int length = Math.min(bytes.length, 32);
        System.arraycopy(bytes, bytes.length - length, out, offset + 32 - length, length);
    }

    /// Shows the prompt with `title` and `reason`, then signs `message` (SHA256withECDSA,
    /// DER). Null on anything but a signature; `lastStatus` says why.
    public static byte[] sign(final Activity activity, String tag, final byte[] message,
                              final String title, final String reason, final String cancel) {
        final Signature signature;
        try {
            KeyStore store = KeyStore.getInstance(PROVIDER);
            store.load(null);
            KeyStore.Entry entry = store.getEntry(PREFIX + tag, null);
            if (!(entry instanceof KeyStore.PrivateKeyEntry)) { lastStatus = 3; return null; }
            PrivateKey key = ((KeyStore.PrivateKeyEntry) entry).getPrivateKey();
            signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(key);
        } catch (KeyPermanentlyInvalidatedException e) {
            lastStatus = 2;
            return null;
        } catch (Throwable t) {
            lastStatus = 4;
            return null;
        }

        final CountDownLatch done = new CountDownLatch(1);
        final byte[][] result = new byte[1][];
        final int[] status = {4};
        final Executor main = activity.getMainExecutor();
        activity.runOnUiThread(() -> {
            try {
                BiometricPrompt.Builder builder = new BiometricPrompt.Builder(activity)
                        .setTitle(title)
                        .setNegativeButton(cancel, main, (dialog, which) -> { status[0] = 1; done.countDown(); });
                if (reason != null && !reason.isEmpty()) builder.setSubtitle(reason);
                BiometricPrompt prompt = builder.build();
                prompt.authenticate(new BiometricPrompt.CryptoObject(signature), new CancellationSignal(), main,
                        new BiometricPrompt.AuthenticationCallback() {
                            @Override
                            public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult outcome) {
                                try {
                                    Signature unlocked = outcome.getCryptoObject().getSignature();
                                    unlocked.update(message);
                                    result[0] = unlocked.sign();
                                    status[0] = 0;
                                } catch (Throwable t) {
                                    status[0] = 4;
                                }
                                done.countDown();
                            }

                            @Override
                            public void onAuthenticationError(int code, CharSequence text) {
                                boolean cancelled = code == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED
                                        || code == BiometricPrompt.BIOMETRIC_ERROR_CANCELED
                                        || code == BiometricPrompt.BIOMETRIC_ERROR_NEGATIVE_BUTTON;
                                status[0] = cancelled ? 1 : 4;
                                done.countDown();
                            }
                            // onAuthenticationFailed: a face or finger not recognised; the prompt stays.
                        });
            } catch (Throwable t) {
                status[0] = 4;
                done.countDown();
            }
        });
        try {
            done.await();
        } catch (InterruptedException e) {
            status[0] = 1;
        }
        lastStatus = status[0];
        return result[0];
    }

    public static synchronized boolean delete(Context context, String tag) {
        try {
            KeyStore store = KeyStore.getInstance(PROVIDER);
            store.load(null);
            String alias = PREFIX + tag;
            if (!store.containsAlias(alias)) return false;
            store.deleteEntry(alias);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }
}
