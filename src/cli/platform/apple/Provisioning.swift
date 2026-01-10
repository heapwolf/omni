// omni provision. Ensures a development certificate, App ID, device and
// profile, then writes the profile into the app directory. Idempotent.
// Development only; distribution is OD-24. Untested: needs a real team.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

enum ProvisionError: Error, CustomStringConvertible {
    case unsupportedHost
    case noCredentials
    /// status is nil for errors that never got as far as an HTTP response
    /// (curl itself failing, a non-JSON body) — only a real response with a
    /// status code lets callers like device() add a status-specific hint.
    case api(status: Int?, message: String)
    case noDevice(String)
    case needsInput(String)

    var description: String {
        switch self {
        case .unsupportedHost:
            return "omni provision needs macOS: it signs ES256 with CryptoKit and uses security(1)."
        case .noCredentials:
            return """
                No App Store Connect credentials. Run:

                  omni provision --login

                CI: set ASC_ISSUER_ID, ASC_KEY_ID and ASC_KEY_PATH instead.
                """
        case .api(_, let message): return "App Store Connect: \(message)"
        case .noDevice(let detail): return detail
        case .needsInput(let what):
            return """
                omni provision --login needs \(what).

                Without a terminal, set ASC_ISSUER_ID, ASC_KEY_ID and ASC_KEY_PATH instead.
                """
        }
    }
}

/// Apple's error responses are JSON:API — {"errors": [{"title", "detail", ...}]}
/// — and a raw dump of that is not something a person should have to parse by
/// eye. This pulls out just the human-readable parts, falling back to the raw
/// body only when it genuinely isn't in that shape.
private func friendlyAPIMessage(method: String, path: String, status: Int, bodyText: String) -> String {
    guard let data = bodyText.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let errors = json["errors"] as? [[String: Any]],
          let first = errors.first,
          let title = first["title"] as? String else {
        return "\(method) \(path) returned \(status)"
    }
    let detail = first["detail"] as? String
    return [title, detail].compactMap { $0 }.joined(separator: " — ") + " (\(status))"
}

// MARK: - Credentials

struct ASCCredentials {
    let issuerId: String
    let keyId: String
    let privateKeyPEM: String

    /// Login keychain: not synced, not in backups.
    private static let service = "omni.appstoreconnect"

    static func resolve() throws -> ASCCredentials {
        if let stored = fromKeychain() { return stored }
        if let environment = fromEnvironment() { return environment }
        throw ProvisionError.noCredentials
    }

    private static func fromKeychain() -> ASCCredentials? {
        guard let json = try? Shell.run(
                "security find-generic-password -s \(service) -w 2>/dev/null"),
              let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let issuerId = fields["issuerId"], let keyId = fields["keyId"],
              let pem = fields["privateKey"] else { return nil }
        return ASCCredentials(issuerId: issuerId, keyId: keyId, privateKeyPEM: pem)
    }

    private static func fromEnvironment() -> ASCCredentials? {
        let environment = ProcessInfo.processInfo.environment
        guard let issuerId = environment["ASC_ISSUER_ID"],
              let keyId = environment["ASC_KEY_ID"] else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = environment["ASC_KEY_PATH"]
            ?? "\(home)/.appstoreconnect/private_keys/AuthKey_\(keyId).p8"
        guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return ASCCredentials(issuerId: issuerId, keyId: keyId, privateKeyPEM: pem)
    }

    static func store(issuerId: String, keyId: String, keyPath: String) throws {
        let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
        let payload = ["issuerId": issuerId, "keyId": keyId, "privateKey": pem]
        let json = try JSONSerialization.data(withJSONObject: payload)

        #if canImport(Security)
        // SecItemAdd, not security(1): its -w takes the secret as an argument,
        // which puts it in the process list.
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "omni"
        ]
        SecItemDelete(identity as CFDictionary)
        var item = identity
        item[kSecValueData as String] = json
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProvisionError.api(status: nil, message: "the keychain refused the credentials (OSStatus \(status))")
        }
        #else
        throw ProvisionError.unsupportedHost
        #endif
    }
}

// MARK: - The API

struct ASC {
    let credentials: ASCCredentials

    #if canImport(CryptoKit)
    /// ES256, 20 minutes. Apple rejects longer.
    private func token() throws -> String {
        let header = ["alg": "ES256", "kid": credentials.keyId, "typ": "JWT"]
        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": credentials.issuerId,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1"
        ]

        func segment(_ object: Any) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64URL
        }

        let signingInput = "\(try segment(header)).\(try segment(payload))"
        let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(signature.rawRepresentation.base64URL)"
    }
    #else
    private func token() throws -> String { throw ProvisionError.unsupportedHost }
    #endif

    @discardableResult
    func request(_ method: String, _ path: String, body: [String: Any]? = nil) throws -> [String: Any] {
        let jwt = try token()
        let directory = NSTemporaryDirectory()
        let configPath = directory + "omni-asc-config-\(UUID().uuidString)"
        let bodyPath = directory + "omni-asc-body-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: configPath)
            try? FileManager.default.removeItem(atPath: bodyPath)
        }

        // Config file, not arguments: a bearer token on the command line is readable
        // by every process.
        //
        // globoff: Apple's filter[x]=y query syntax has literal [ ] in it,
        // which curl otherwise parses as a glob range and rejects with
        // "bad range in URL" (exit 3) before ever making the request.
        var config = """
            url = "https://api.appstoreconnect.apple.com\(path)"
            request = "\(method)"
            header = "Authorization: Bearer \(jwt)"
            header = "Content-Type: application/json"
            silent
            show-error
            write-out = "\\n%{http_code}"
            globoff
            """
        if let body {
            let data = try JSONSerialization.data(withJSONObject: body)
            try data.write(to: URL(fileURLWithPath: bodyPath))
            config += "\ndata = \"@\(bodyPath)\""
        }
        try config.write(toFile: configPath, atomically: true, encoding: .utf8)

        let result = try Shell.exec("/usr/bin/curl", ["--config", configPath])
        guard result.status == 0 else {
            throw ProvisionError.api(status: nil, message: "curl exited \(result.status)")
        }

        // Status is the last line.
        var lines = result.output.split(separator: "\n", omittingEmptySubsequences: false)
        let status = Int(lines.removeLast().trimmingCharacters(in: .whitespaces)) ?? 0
        let bodyText = lines.joined(separator: "\n")

        guard (200..<300).contains(status) else {
            throw ProvisionError.api(
                status: status,
                message: friendlyAPIMessage(method: method, path: path, status: status, bodyText: bodyText))
        }
        guard !bodyText.isEmpty else { return [:] }
        guard let data = bodyText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProvisionError.api(status: status, message: "\(method) \(path) returned something that is not JSON")
        }
        return json
    }

    static func rows(_ response: [String: Any]) -> [[String: Any]] {
        response["data"] as? [[String: Any]] ?? []
    }

    static func attributes(_ row: [String: Any]) -> [String: Any] {
        row["attributes"] as? [String: Any] ?? [:]
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
