// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Omni",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        // The CLI tool
        .executable(name: "omni", targets: ["omni"]),
        // The UI Framework that user apps will import
        .library(name: "OmniUI", targets: ["OmniUI"]),
        // Capability modules. Each is its own product so an app takes only what it uses.
        .library(name: "OmniHTTP", targets: ["OmniHTTP"]),
        .library(name: "OmniKeychain", targets: ["OmniKeychain"]),
        .library(name: "OmniCamera", targets: ["OmniCamera"]),
        // The end-to-end test agent. For a test build only: a shipped app never links it.
        .library(name: "OmniProbe", targets: ["OmniProbe"]),

        // The SwiftData reproduction module
        .library(name: "OmniData", targets: ["OmniData"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // 1. The CLI Builder
        .executableTarget(
            name: "omni",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "src/cli"
        ),

        // 2. The view engine
        .target(
            name: "OmniUI",
            dependencies: [
                .target(name: "CAndroid", condition: .when(platforms: [.android])),
                .target(name: "CWindows", condition: .when(platforms: [.windows]))
            ],
            path: "src/ui",
            exclude: [
                "android/OmniEventBridge.java", "android/OmniCanvasView.java",
                "android/OmniFileProvider.java", "android/OmniKeystore.java",
                "android/OmniWebView.java", "android/OmniSymbol.java",
                "android/OmniDeviceKey.java"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // 3. Data Persistence & Querying (SwiftData Clone)
        .target(
            name: "OmniData",
            dependencies: [
                "OmniUI",
                "CSQLite" // <--- Add this dependency
            ],
            path: "src/data",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // 4. The platform's HTTP, and nothing above it.
        .target(
            name: "OmniHTTP",
            path: "src/http",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // 5. Secure storage, and the device's own signing key.
        .target(
            name: "OmniKeychain",
            dependencies: [
                .target(name: "CAndroid", condition: .when(platforms: [.android]))
            ],
            path: "src/keychain",
            // Java, built into the APK by omni's Android build when omni.json asks.
            exclude: ["android/play-integrity"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // 6. Capture.
        .target(
            name: "OmniCamera",
            dependencies: [
                .target(name: "CAndroid", condition: .when(platforms: [.android]))
            ],
            path: "src/camera",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // 7. The Android JNI C-Bridge
        .target(
            name: "CAndroid",
            path: "src/bridge/android",
            publicHeadersPath: "."
        ),

        // 8. The Windows C-ABI Bridge
        .target(
            name: "CWindows",
            path: "src/bridge/windows",
            publicHeadersPath: "."
        ),

        // SQLite C-brige
        .target(
            name: "CSQLite",
            path: "src/bridge/sqlite",
            publicHeadersPath: "include",
            cSettings: [
                // Optional but recommended standard SQLite compiler flags
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_RTREE"),
                .define("SQLITE_ENABLE_SESSION"),
                .define("SQLITE_ENABLE_PREUPDATE_HOOK"),
                .unsafeFlags(["-Wno-ambiguous-macro"])
            ]
        ),

        // --- Tests ---
        // 9. Drives an app from inside, for end-to-end tests.
        .target(
            name: "OmniProbe",
            dependencies: ["OmniUI", "OmniHTTP"],
            path: "src/probe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "OmniProbeTests",
            dependencies: ["OmniProbe", "OmniUI"],
            path: "tests/OmniProbeTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OmniUITests",
            dependencies: ["OmniUI"],
            path: "tests/OmniUITests",
            // Read from the source tree by path (FontTests), not bundled.
            exclude: ["Fixtures"]
        ),
        /* .testTarget(
            name: "OmniDataTests",
            dependencies: ["OmniData"],
            path: "tests/OmniDataTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ), */
        .testTarget(
            name: "OmniCameraTests",
            dependencies: ["OmniCamera"],
            path: "tests/OmniCameraTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OmniKeychainTests",
            dependencies: ["OmniKeychain"],
            path: "tests/OmniKeychainTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OmniHTTPTests",
            dependencies: ["OmniHTTP"],
            path: "tests/OmniHTTPTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
