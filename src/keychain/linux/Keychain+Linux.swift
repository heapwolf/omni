
#if os(Linux)
import Foundation

func makePlatformStore() -> any KeychainStore { FileKeychainStore() }

public struct FileKeychainStore: KeychainStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map(URL.init(fileURLWithPath:))
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
            // The app's own, as OmniUI's AppDirectories.support is. One folder
            // for every omni app let any of them read another's secrets.
            self.directory = base.appendingPathComponent(ProcessInfo.processInfo.processName)
                .appendingPathComponent("keychain")
        }
    }

    /// Keys become filenames, so they are hashed rather than trusted: a key
    /// containing "../" must not escape the directory.
    private func path(_ key: String) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Data(key.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return directory.appendingPathComponent(String(format: "%016llx", hash))
    }

    public func set(_ data: Data, for key: String, accessibility: Accessibility) throws {
        // Accessibility has no analogue here: there is no lock state to gate
        // on. Ignored rather than silently pretended.
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: path(key), options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: path(key).path)
        } catch {
            throw KeychainError.platform(code: (error as NSError).code,
                                         message: error.localizedDescription)
        }
    }

    public func get(_ key: String) throws -> Data? {
        let url = path(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try Data(contentsOf: url) }
        catch {
            throw KeychainError.platform(code: (error as NSError).code,
                                         message: error.localizedDescription)
        }
    }

    public func delete(_ key: String) throws {
        let url = path(key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KeychainError.notFound
        }
        do { try FileManager.default.removeItem(at: url) }
        catch {
            throw KeychainError.platform(code: (error as NSError).code,
                                         message: error.localizedDescription)
        }
    }
}
#endif
