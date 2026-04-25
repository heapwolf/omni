// Fetched, not vendored: the static loaders are 10 MB per architecture.

import Foundation

struct WebView2SDK {
    /// Pinned.
    static let version = "1.0.2792.45"

    let root: String
    /// Set by OMNI_WEBVIEW2_SDK: nothing is downloaded and a missing file is the
    /// caller's mistake.
    let isVendored: Bool

    private let fm = FileManager.default
    private let env = ProcessInfo.processInfo.environment

    init() {
        let environment = ProcessInfo.processInfo.environment
        if let vendored = environment["OMNI_WEBVIEW2_SDK"], !vendored.isEmpty {
            root = vendored
            isVendored = true
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let toolchain = environment["OMNI_TOOLCHAIN"] ?? "\(home)/.omni/toolchain"
            root = "\(toolchain)/webview2-\(Self.version)"
            isVendored = false
        }
    }

    struct Paths {
        let includeDirectory: String
        let loaderLibrary: String
        /// WebView2Loader.dll must ship beside the .exe.
        let requiresLoaderDLL: Bool
    }

    var isPresent: Bool {
        fm.fileExists(atPath: "\(root)/build/native/include/WebView2.h")
    }

    /// Downloads and unpacks if needed, then returns the paths a build needs.
    /// Throws when the package is present but malformed.
    func ensure(architecture: String = "x64") throws -> Paths {
        if !isPresent {
            guard !isVendored else {
                throw WebView2Error.malformed(
                    "OMNI_WEBVIEW2_SDK is \(root), but there is no build/native/include/WebView2.h under it.")
            }
            try fetch()
        }

        let include = "\(root)/build/native/include"
        guard fm.fileExists(atPath: "\(include)/WebView2.h") else {
            throw WebView2Error.malformed("no WebView2.h under \(include)")
        }

        // Static first; the import library is the fallback.
        let architectureDirectory = "\(root)/build/native/\(architecture)"
        let staticLoader = "\(architectureDirectory)/WebView2LoaderStatic.lib"
        if fm.fileExists(atPath: staticLoader) {
            return Paths(includeDirectory: include, loaderLibrary: staticLoader,
                         requiresLoaderDLL: false)
        }

        let importLoader = "\(architectureDirectory)/WebView2Loader.dll.lib"
        guard fm.fileExists(atPath: importLoader) else {
            throw WebView2Error.malformed("""
                no loader library for \(architecture) in \(architectureDirectory) — \
                expected WebView2LoaderStatic.lib or WebView2Loader.dll.lib. \
                The package ships x64, arm64 and x86; check the architecture name.
                """)
        }
        return Paths(includeDirectory: include, loaderLibrary: importLoader,
                     requiresLoaderDLL: true)
    }

    /// A .nupkg is a zip served over HTTPS.
    private func fetch() throws {
        let url = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/\(Self.version)"
        let archive = "\(root).nupkg"

        try fm.createDirectory(atPath: (root as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)

        Console.info("WebView2 SDK \(Self.version)")
        // -f so an HTML error page is not unzipped as the package; -L for redirects.
        let curl = try Shell.exec("/usr/bin/curl",
            ["-fsSL", "--retry", "3", "--retry-delay", "2", "-o", archive, url])
        guard curl.status == 0 else {
            throw WebView2Error.download("curl exited \(curl.status): \(curl.output)")
        }

        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        let unzip = try Shell.exec("/usr/bin/unzip", ["-q", "-o", archive, "-d", root])
        guard unzip.status == 0 else {
            throw WebView2Error.download("unzip exited \(unzip.status): \(unzip.output)")
        }
        try? fm.removeItem(atPath: archive)
    }
}

enum WebView2Error: Error, CustomStringConvertible {
    case download(String)
    case malformed(String)

    var description: String {
        switch self {
        case .download(let detail):
            return "Could not fetch the WebView2 SDK: \(detail)"
        case .malformed(let detail):
            return "The WebView2 SDK is not laid out as expected: \(detail)"
        }
    }
}
