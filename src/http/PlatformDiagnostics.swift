
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PlatformDiagnostics {
    /// Maps a platform error onto HTTPError, naming the cause where known.
    public static func diagnose(_ error: Error, url: URL) -> HTTPError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timedOut
            case .cancelled: return .cancelled
            case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed:
                return .transport("TLS handshake with \(host(url)) failed. \(caStoreHint)")
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .transport("The certificate for \(host(url)) was not trusted. \(caStoreHint)")
            case .notConnectedToInternet:
                return .transport("No network. On Android this is also what a missing android.permission.INTERNET looks like — check the manifest before the signal.")
            case .cannotFindHost:
                return .transport("Could not resolve \(host(url)). On an emulator, the host machine is 10.0.2.2, not localhost.")
            case .cannotConnectToHost:
                return .transport("Could not connect to \(host(url)):\(url.port.map(String.init) ?? "default"). On an emulator, the host machine is 10.0.2.2, not localhost.")
            default: break
            }
        }

        let description = (error as NSError).localizedDescription

        // Cleartext is refused before a socket opens, and the platform message says
        // only that the connection failed.
        if url.scheme == "http" {
            return .transport("Cleartext HTTP to \(host(url)) was refused. Android blocks it from targetSdk 28 unless android:usesCleartextTraffic is set. Underlying error: \(description)")
        }

        return .transport(description)
    }

    private static func host(_ url: URL) -> String { url.host ?? "the host" }

    /// curl inside FoundationNetworking honours SSL_CERT_FILE and SSL_CERT_DIR.
    private static let caStoreHint =
        "Android's trust store is /system/etc/security/cacerts; set SSL_CERT_DIR or SSL_CERT_FILE if it is not being found. A proxy with its own root needs that root installed as a user CA and trusted by the app's network security config."

    public static func startupDiagnostic() -> String? {
        #if os(Android)
        if ProcessInfo.processInfo.environment["SSL_CERT_DIR"] == nil,
           !FileManager.default.fileExists(atPath: "/system/etc/security/cacerts") {
            return "No CA store at /system/etc/security/cacerts and SSL_CERT_DIR is unset — HTTPS will fail certificate verification."
        }
        #endif
        return nil
    }
}
