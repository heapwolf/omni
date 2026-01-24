// swift-tools-version: 6.0
import PackageDescription

// An ordinary Omni app, structured exactly as any third-party project
// consuming the framework would be — a local path dependency on the
// framework's own package, not a target baked into it. The omni CLI finds
// this manifest itself (AppleBuild/AndroidBuild's packageRoot() walks up
// from --app-path looking for the nearest Package.swift), so nothing in the
// CLI needs to know this app exists.
let package = Package(
    name: "smoke",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    dependencies: [
        .package(name: "Omni", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "smoke",
            dependencies: [
                .product(name: "OmniUI", package: "Omni")
            ],
            path: ".",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
