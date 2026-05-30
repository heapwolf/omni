// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "todo",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    dependencies: [
        .package(name: "Omni", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "todo",
            dependencies: [
                .product(name: "OmniUI", package: "Omni"),
                .product(name: "OmniData", package: "Omni")
            ],
            path: ".",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
