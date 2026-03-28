// src/ui/android/OmniDeviceKey.java
package com.omni;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import java.math.BigInteger;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.ProviderException;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;

/// OmniKeychain's device keys: P-256 signing keys made inside the Android
/// Keystore, so the private half never reaches the app. StrongBox where the
/// phone has it, else the TEE. No user authentication and no unlocked-device
/// restriction: a refresh may sign while the phone is locked.
public final class OmniDeviceKey {
    private static final String PROVIDER = "AndroidKeyStore";
    private static final String PREFIX = "omni.devicekey.";

    private OmniDeviceKey() {}

    /// The key under `tag`, made first if there is none. Synchronized: two
    /// first uses at once must not make two keys.
    private static synchronized KeyStore.PrivateKeyEntry entry(Context context, String tag) throws Exception {
        String alias = PREFIX + tag;
        KeyStore store = KeyStore.getInstance(PROVIDER);
        store.load(null);

        KeyStore.Entry existing = store.getEntry(alias, null);
        if (existing instanceof KeyStore.PrivateKeyEntry) {
            return (KeyStore.PrivateKeyEntry) existing;
        }

        boolean strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                && context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE);
        if (strongBox) {
            try {
                generate(alias, true);
            } catch (ProviderException e) {
                // StrongBoxUnavailableException is a ProviderException, and is
                // named here by its parent so older releases load this class.
                generate(alias, false);
            }
        } else {
            generate(alias, false);
        }
        return (KeyStore.PrivateKeyEntry) store.getEntry(alias, null);
    }

    private static void generate(String alias, boolean strongBox) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER);
        KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256);
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setIsStrongBoxBacked(true);
        }
        generator.initialize(spec.build());
        generator.generateKeyPair();
    }

    /// x9.63 uncompressed, 65 bytes: 0x04, then x and y as 32 bytes each,
    /// the same as iOS gives. Null if the key could not be made or read.
    public static byte[] publicKey(Context context, String tag) {
        try {
            ECPublicKey key = (ECPublicKey) entry(context, tag).getCertificate().getPublicKey();
            byte[] out = new byte[65];
            out[0] = 0x04;
            put(key.getW().getAffineX(), out, 1);
            put(key.getW().getAffineY(), out, 33);
            return out;
        } catch (Throwable t) {
            return null;
        }
    }

    /// A coordinate as exactly 32 bytes: BigInteger's own may carry a sign
    /// byte, or be shorter.
    private static void put(BigInteger coordinate, byte[] out, int offset) {
        byte[] bytes = coordinate.toByteArray();
        int length = Math.min(bytes.length, 32);
        System.arraycopy(bytes, bytes.length - length, out, offset + 32 - length, length);
    }

    /// ECDSA over SHA-256 of `message`, DER, as SHA256withECDSA gives it.
    /// Null on failure.
    public static byte[] sign(Context context, String tag, byte[] message) {
        try {
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(entry(context, tag).getPrivateKey());
            signature.update(message);
            return signature.sign();
        } catch (Throwable t) {
            return null;
        }
    }

    /// Returns true if there was a key to remove.
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
