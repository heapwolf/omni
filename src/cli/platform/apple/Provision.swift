// The ensure-loop. API client: Provisioning.swift.

import Foundation

struct Provisioner {
    let path: String

    private var manifest: OmniManifest { OmniManifest.load(from: path) }

    // MARK: Login

    func login() throws {
        let keyPath = try key()
        let keyId = try identifier(of: keyPath)
        // Same page as the key, above the list.
        let issuerId = try ask("Issuer ID (appstoreconnect.apple.com/access/integrations/api)",
                               "an issuer ID")
        try ASCCredentials.store(issuerId: issuerId, keyId: keyId, keyPath: keyPath)
        Console.success("Stored in the login keychain.")

        // The key is safely in the keychain now; the loose .p8 on disk is
        // just unnecessary exposure from here on. Deleting it is still the
        // user's call, not automatic — they may want a backup, and Apple
        // will not let them re-download this exact file.
        if confirm("Delete \(keyPath) now that it's stored?") {
            do {
                try FileManager.default.removeItem(atPath: keyPath)
                Console.success("Deleted \(keyPath).")
            } catch {
                Console.warning("Could not delete \(keyPath): \(error.localizedDescription)")
            }
        }
    }

    /// Apple names the download AuthKey_<KeyID>.p8, which is how identifier(of:)
    /// recovers the key ID for free — but a renamed key (a project-specific
    /// name like `example.p8`) is just as valid a private key, so the scan
    /// itself only requires the .p8 extension. identifier(of:) falls back to
    /// asking when the AuthKey_ prefix isn't there to parse.
    private func key() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let found = ["\(home)/.appstoreconnect/private_keys", "\(home)/Downloads"]
            .flatMap { directory in
                ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
                    .filter { $0.hasSuffix(".p8") }
                    .sorted()
                    .map { "\(directory)/\($0)" }
            }

        if found.count == 1 {
            Console.info(found[0])
            return found[0]
        }
        if found.count > 1 {
            for (index, path) in found.enumerated() { print("  \(index + 1). \(path)") }
            let choice = Int(try ask("Which key", "a choice")) ?? 0
            guard found.indices.contains(choice - 1) else {
                throw ProvisionError.needsInput("a number from the list")
            }
            return found[choice - 1]
        }

        // Nothing to automate: the API authenticates with a key, so it cannot
        // issue the first one. Key management is web-only.
        Console.info("No API key found. This part is manual, once:")
        print("""

              https://appstoreconnect.apple.com/access/integrations/api

            Generate a key with the Admin or App Manager role. An "Individual"
            key just inherits your own role on the team — if your account is
            only Developer there, ask a Team Admin to either raise it or
            generate a Team Key with Admin or App Manager directly. Developer
            is enough for everything else this tool does (certificates,
            bundle IDs, profiles); only registering a new device needs the
            higher role. Download the .p8; Apple offers it once.

            """)
        let entered = try ask("Path to the .p8", "a path")
        let path = NSString(string: entered).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProvisionError.needsInput("a path that exists; \(path) does not")
        }
        return path
    }

    private func identifier(of keyPath: String) throws -> String {
        let name = (keyPath as NSString).lastPathComponent
        if name.hasPrefix("AuthKey_"), name.hasSuffix(".p8") {
            return String(name.dropFirst(8).dropLast(3))
        }
        return try ask("Key ID (appstoreconnect.apple.com/access/integrations/api, next to the key's name — 10 characters, not the name itself)", "a key ID")
    }

    private func ask(_ label: String, _ missing: String) throws -> String {
        print("\(label): ", terminator: "")
        fflush(nil)
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces), !answer.isEmpty else {
            throw ProvisionError.needsInput(missing)
        }
        return answer
    }

    /// Defaults to No: a missing terminal (empty readLine) or a plain Enter
    /// both decline, so this never deletes anything without an explicit "y".
    private func confirm(_ question: String) -> Bool {
        print("\(question) [y/N]: ", terminator: "")
        fflush(nil)
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return answer == "y" || answer == "yes"
    }

    func run(product: String) throws {
        #if !canImport(CryptoKit)
        throw ProvisionError.unsupportedHost
        #else
        // Fail fast: a connected device is a free, local check, so there is
        // no point creating a certificate or bundle ID on Apple's side (both
        // real, side-effecting API calls) only to fail on this one after.
        let udid = try connectedUDID()

        let api = ASC(credentials: try ASCCredentials.resolve())
        let bundleId = manifest.bundleIdentifier ?? "com.omniswift.\(product.lowercased())"

        let certificateId = try certificate(api)
        let bundleRecordId = try bundle(api, identifier: bundleId, name: product)
        let deviceId = try device(api, udid: udid)
        let profile = try profile(api, bundle: bundleRecordId,
                                  certificate: certificateId, device: deviceId, name: bundleId)

        guard let decoded = Data(base64Encoded: profile, options: .ignoreUnknownCharacters) else {
            throw ProvisionError.api(status: nil, message: "profile content was not base64")
        }
        let destination = ProvisioningProfile.location(appPath: path, bundleIdentifier: bundleId)
        try FileManager.default.createDirectory(
            atPath: (destination as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try decoded.write(to: URL(fileURLWithPath: destination))
        // Readable by you alone.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination)
        Console.success(destination)
        if let legacy = ProvisioningProfile.legacy(in: path) {
            Console.warning("\(legacy) is an old profile inside the project; it is no longer needed. Delete it.")
        }
        #endif
    }

    // MARK: Certificate

    /// A portal certificate is useless without its private key, so the local
    /// keychain decides. Creating one is announced: they are limited and shared.
    private func certificate(_ api: ASC) throws -> String {
        let local = (try? Shell.run("security find-identity -v -p codesigning")) ?? ""
        let rows = ASC.rows(try api.request("GET", "/v1/certificates?filter[certificateType]=IOS_DEVELOPMENT"))

        // Matched by the certificate's own Subject Common Name — the same
        // name `security find-identity` lists a local keychain identity
        // under — not Apple's "name"/"displayName" attribute, which is just
        // a generic label ("iOS Development: Created via API") with no
        // relationship to the identity string in the certificate itself.
        // Comparing against that label meant this could never find a real
        // local match even when one genuinely existed (Xcode's own
        // automatic signing, or a certificate this same tool created on
        // this same machine in an earlier run) — every run looked like it
        // needed a brand new certificate, straight into Apple's cap.
        for row in rows {
            guard let content = ASC.attributes(row)["certificateContent"] as? String,
                  let commonName = Self.subjectCommonName(ofCertificateBase64: content),
                  local.contains(commonName),
                  let id = row["id"] as? String else { continue }
            return id
        }

        Console.info("No development certificate with a local private key. Creating one.")
        let csr = try makeCSR()
        do {
            return try requestCertificate(api, csr: csr)
        } catch ProvisionError.api(status: 409, let message) where message.contains("already have a current") {
            // Apple caps how many iOS Development certificates a team can
            // have active at once. None of the existing ones matched a
            // private key on this machine (checked above) — but a
            // certificate isn't scoped to one app or org, it's shared
            // across everything this team signs, so that alone does not
            // mean any of them are safe to revoke: the matching private key
            // could just as easily be on a teammate's machine or a CI
            // runner as be lost. This tool cannot tell the difference, so
            // the portal — where whoever manages the team can see who
            // actually holds each one — is the real first step, not this
            // prompt.
            guard !rows.isEmpty else {
                throw ProvisionError.api(status: 409, message: """
                    \(message)
                    That's likely a pending certificate request rather than an issued certificate — \
                    review it at appstoreconnect.apple.com/account/resources/certificates/list.
                    """)
            }
            Console.warning("Apple refused to create a new certificate: this team already has \(rows.count), and none match a private key on this machine.")
            print("""

                Apple caps how many active iOS Development certificates a team can have at once, \
                and this team is already at that cap — that's why creating a new one just failed, \
                not a choice this tool is making. There are two ways forward: find the private key \
                for one of the existing certificates below (another Mac, an exported .p12, iCloud \
                Keychain) and import it instead of creating a new one — nothing has to be revoked \
                for that — or free up a slot by revoking one.

                A development certificate isn't scoped to one app or org — it's shared across \
                everything this team signs, so "no local private key" alone does not mean any of \
                these are safe to revoke; the key could just as easily be on a teammate's machine, \
                a CI runner, or hold a different project on this same team. Only ones this tool can \
                positively identify as its own — by the certificate's Subject Common Name, \
                "\(Self.ownCertificateCommonName)" — are ever offered below for revoking; anything \
                else is listed for visibility only. When in doubt, check
                https://appstoreconnect.apple.com/account/resources/certificates/list yourself.

                """)

            var selectable: [Int: String] = [:]
            for row in rows {
                let attrs = ASC.attributes(row)
                let name = attrs["name"] as? String ?? "(unnamed)"
                let serial = attrs["serialNumber"] as? String ?? "unknown serial"
                let expires = attrs["expirationDate"] as? String ?? "unknown expiration"
                let cn = (attrs["certificateContent"] as? String).flatMap(Self.subjectCommonName(ofCertificateBase64:))

                if cn == Self.ownCertificateCommonName, let id = row["id"] as? String {
                    let number = selectable.count + 1
                    selectable[number] = id
                    print("  \(number). \(name) — serial \(serial), expires \(expires) — created by this tool")
                } else {
                    print("  -  \(name) — serial \(serial), expires \(expires) — \(cn.map { "CN: \($0)" } ?? "not created by this tool")")
                }
            }

            guard !selectable.isEmpty else {
                throw ProvisionError.api(status: 409, message: """
                    \(message)
                    None of these are identifiable as created by this tool, so it will not offer to \
                    revoke any of them. Revoke one yourself at \
                    appstoreconnect.apple.com/account/resources/certificates/list, then re-run.
                    """)
            }
            print("Revoke which one? Enter its number, or press Enter to stop and handle it yourself: ", terminator: "")
            fflush(nil)
            let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let choice = Int(input), let id = selectable[choice] else {
                throw ProvisionError.api(status: 409, message: """
                    \(message)
                    Revoke one yourself at appstoreconnect.apple.com/account/resources/certificates/list, \
                    then re-run.
                    """)
            }
            _ = try? api.request("DELETE", "/v1/certificates/\(id)")
            return try requestCertificate(api, csr: csr)
        }
    }

    private func requestCertificate(_ api: ASC, csr: String) throws -> String {
        let created = try api.request("POST", "/v1/certificates", body: [
            "data": ["type": "certificates",
                     "attributes": ["certificateType": "IOS_DEVELOPMENT", "csrContent": csr]]
        ])
        guard let row = created["data"] as? [String: Any], let id = row["id"] as? String,
              let content = ASC.attributes(row)["certificateContent"] as? String else {
            throw ProvisionError.api(status: nil, message: "certificate response had no id")
        }
        try importCertificate(content)
        return id
    }

    /// Every certificate this tool ever requests carries this exact Subject
    /// Common Name — the one fact that lets a later run tell "created by
    /// omni" apart from "created by Xcode, fastlane, a teammate, or a
    /// different tool entirely" when deciding what is even safe to *offer*
    /// to revoke. Development certificates aren't scoped to one app or team
    /// role, so a generic Apple-assigned label like "Created via API" gives
    /// no such signal on its own.
    static let ownCertificateCommonName = "omni development"

    private func makeCSR() throws -> String {
        let directory = NSTemporaryDirectory()
        let keyPath = directory + "omni-signing-key.pem"
        let csrPath = directory + "omni-signing.csr"
        try Shell.checked(
            "openssl req -new -newkey rsa:2048 -nodes -keyout \(keyPath) -out \(csrPath) "
            + "-subj \"/CN=\(Self.ownCertificateCommonName)/C=US\"",
            step: "generating a signing request")
        // Imported now: the key must be in the keychain before the certificate
        // Apple returns can pair with it.
        try Shell.checked("security import \(keyPath) -k ~/Library/Keychains/login.keychain-db -x -A",
                          step: "importing the private key")
        try? FileManager.default.removeItem(atPath: keyPath)
        return try String(contentsOfFile: csrPath, encoding: .utf8)
    }

    /// The Subject Common Name baked into a DER certificate, straight from
    /// the same Security framework `security(1)` itself uses — not text
    /// Apple assigns (its "name"/"displayName" attributes are just a label
    /// like "iOS Development: Created via API", identical for every
    /// API-created certificate regardless of who made it). Returns nil for
    /// anything unreadable, which the caller treats as "cannot be identified
    /// as ours" — fails closed rather than guessing.
    #if canImport(Security)
    private static func subjectCommonName(ofCertificateBase64 base64: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let certificate = SecCertificateCreateWithData(nil, data as CFData) else { return nil }
        var commonName: CFString?
        guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess else { return nil }
        return commonName as String?
    }
    #else
    private static func subjectCommonName(ofCertificateBase64 base64: String) -> String? { nil }
    #endif

    private func importCertificate(_ base64: String) throws {
        let cerPath = NSTemporaryDirectory() + "omni-signing.cer"
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw ProvisionError.api(status: nil, message: "certificate content was not base64")
        }
        try data.write(to: URL(fileURLWithPath: cerPath))
        try Shell.checked("security import \(cerPath) -k ~/Library/Keychains/login.keychain-db -A",
                          step: "importing the certificate")
    }

    // MARK: App ID

    private func bundle(_ api: ASC, identifier: String, name: String) throws -> String {
        let existing = ASC.rows(try api.request("GET", "/v1/bundleIds?filter[identifier]=\(identifier)"))
        if let id = existing.first?["id"] as? String { return id }

        let created = try api.request("POST", "/v1/bundleIds", body: [
            "data": ["type": "bundleIds",
                     "attributes": ["identifier": identifier, "name": name, "platform": "IOS"]]
        ])
        guard let id = (created["data"] as? [String: Any])?["id"] as? String else {
            throw ProvisionError.api(status: nil, message: "bundleId response had no id")
        }
        return id
    }

    // MARK: Device

    private func device(_ api: ASC, udid: String) throws -> String {
        let existing = ASC.rows(try api.request("GET", "/v1/devices?filter[udid]=\(udid)"))
        if let id = existing.first?["id"] as? String { return id }

        let created: [String: Any]
        do {
            created = try api.request("POST", "/v1/devices", body: [
                "data": ["type": "devices",
                         "attributes": ["udid": udid, "name": "omni \(udid.prefix(8))", "platform": "IOS"]]
            ])
        } catch ProvisionError.api(status: 403, let message) {
            // The one operation here that needs more than the Developer role
            // an Individual key normally carries — everything else (certs,
            // bundle IDs, profiles) works fine at Developer.
            throw ProvisionError.api(status: 403, message: """
                \(message)
                Registering a device needs an API key with the Admin or App Manager role — Developer isn't enough. \
                Generate a new key with one of those roles at appstoreconnect.apple.com/access/integrations/api, \
                then run `omni provision --login` again.
                """)
        }
        guard let id = (created["data"] as? [String: Any])?["id"] as? String else {
            throw ProvisionError.api(status: nil, message: "device response had no id")
        }
        return id
    }

    /// Ground truth for "is my device actually registered", straight from
    /// Apple's API — not a guess at what a web page shows, since
    /// appstoreconnect.apple.com serves the same single-page-app shell for
    /// every path whether or not it's a real route, so a URL alone can't be
    /// confirmed by whether it "loads".
    func listDevices() throws {
        let api = ASC(credentials: try ASCCredentials.resolve())
        let rows = ASC.rows(try api.request("GET", "/v1/devices"))
        guard !rows.isEmpty else {
            Console.info("Apple's API reports no devices registered on this team.")
            return
        }
        for row in rows {
            let attrs = ASC.attributes(row)
            let name = attrs["name"] as? String ?? "(unnamed)"
            let udid = attrs["udid"] as? String ?? "unknown udid"
            let status = attrs["status"] as? String ?? "unknown status"
            let addedDate = attrs["addedDate"] as? String ?? "unknown date"
            Console.info("\(name) — \(udid) — \(status) — added \(addedDate)")
        }
    }

    private func connectedUDID() throws -> String {
        let listPath = NSTemporaryDirectory() + "omni-devices-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: listPath) }
        try Shell.checked("xcrun devicectl list devices --json-output \"\(listPath)\"",
                          step: "listing devices")

        guard let data = FileManager.default.contents(atPath: listPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]] else {
            throw ProvisionError.noDevice("Could not read the device list.")
        }

        // devicectl remembers every device it has ever paired with, plugged
        // in or not, so we do need to filter — but not on tunnelState ==
        // "connected": that specifically means an active remote-service
        // tunnel, which only comes up while something is mid-operation
        // against the device. A wired, trusted, fully-usable iPhone sits at
        // "disconnected" the rest of the time. "unavailable" is the state
        // that actually means "not here" (never paired, or paired but not
        // currently reachable at all), so that's what gets excluded.
        for entry in devices {
            let properties = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
            guard properties["platform"] as? String == "iOS",
                  let udid = properties["udid"] as? String,
                  connection["tunnelState"] as? String != "unavailable" else { continue }
            return udid
        }
        throw ProvisionError.noDevice("No iOS device connected. Plug one in and unlock it.")
    }

    // MARK: Profile

    /// Regenerated rather than patched: a profile's device and certificate sets
    /// are fixed at creation.
    private func profile(_ api: ASC, bundle: String, certificate: String,
                         device: String, name: String) throws -> String {
        let profileName = "omni \(name) development"
        for row in ASC.rows(try api.request("GET", "/v1/profiles")) {
            guard ASC.attributes(row)["name"] as? String == profileName,
                  let id = row["id"] as? String else { continue }
            try api.request("DELETE", "/v1/profiles/\(id)")
        }

        let body: [String: Any] = [
            "data": [
                "type": "profiles",
                "attributes": ["name": profileName, "profileType": "IOS_APP_DEVELOPMENT"],
                "relationships": [
                    "bundleId": ["data": ["type": "bundleIds", "id": bundle]],
                    "certificates": ["data": [["type": "certificates", "id": certificate]]],
                    "devices": ["data": [["type": "devices", "id": device]]]
                ]
            ]
        ]

        // A device Apple just handed back from POST /v1/devices can take a
        // few seconds to propagate before it's valid to reference here —
        // a documented eventual-consistency gap ("no current iOS devices on
        // this team matching the provided device IDs", 409), not a real
        // problem with the ID. Retry briefly rather than surface a transient
        // ordering issue as a fatal error.
        //
        // If it's still happening after that short retry window, seconds
        // aren't the issue anymore. A brand-new (or just-renewed) Apple
        // Developer Program membership can hold newly registered devices
        // for a day or more before they're usable in a profile — nothing
        // this tool (or waiting a few more seconds) can fix, so say so
        // instead of leaving the raw 409 as the last word.
        var attempt = 0
        while true {
            attempt += 1
            do {
                let created = try api.request("POST", "/v1/profiles", body: body)
                guard let row = created["data"] as? [String: Any],
                      let content = ASC.attributes(row)["profileContent"] as? String else {
                    throw ProvisionError.api(status: nil, message: "profile response had no content")
                }
                return content
            } catch ProvisionError.api(status: 409, let message) where message.contains("no current") {
                guard attempt < 5 else {
                    throw ProvisionError.api(status: 409, message: """
                        \(message)
                        A device Apple just registered goes through a PROCESSING state before it's usable \
                        in a profile — run `omni provision --list-devices` to check: if this device is still \
                        listed as PROCESSING rather than ENABLED, that's the cause, and it's on Apple's side, \
                        not something to retry through. Wait and check again periodically; once it flips to \
                        ENABLED, `omni provision` will succeed.
                        """)
                }
                Console.info("Apple hasn't finished registering the device yet — retrying in \(attempt * 2)s...")
                Thread.sleep(forTimeInterval: Double(attempt * 2))
            }
        }
    }
}
