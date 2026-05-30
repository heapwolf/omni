// swift-tools-version: 6.0
import PackageDescription

// An ordinary Omni app — see ../smoke/Package.swift for why this lives here
// rather than as a set of targets in the framework's own manifest.
//
// omnikitchen (a dynamic library, not the executable) is what Android
// actually loads — MainActivity.java calls System.loadLibrary("omnikitchen")
// — so it has to stay a real product name AndroidBuild's resolveProduct()
// can find via dump-package, the same as when this lived in the root
// manifest.
let package = Package(
    name: "kitchensink",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .library(name: "omnikitchen", type: .dynamic, targets: ["KitchenSinkUI"])
    ],
    dependencies: [
        .package(name: "Omni", path: "../..")
    ],
    targets: [
        .target(
            name: "KitchenSinkUI",
            dependencies: [
                .product(name: "OmniUI", package: "Omni"),
                .product(name: "OmniCamera", package: "Omni"),
                .product(name: "OmniKeychain", package: "Omni")
            ],
            path: "ui",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .executableTarget(
            name: "kitchensink",
            dependencies: [
                .product(name: "OmniUI", package: "Omni"),
                "KitchenSinkUI"
            ],
            path: "desktop",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // Renders every screen the way a person would see it — see the test
        // file itself for what it actually catches. GTK/Linux-only (the
        // test is #if os(Linux)-guarded internally too), so it needs the
        // same libgtk/libcairo the framework's own Linux backend links.
        .testTarget(
            name: "KitchenSinkTests",
            dependencies: [
                .product(name: "OmniUI", package: "Omni"),
                "KitchenSinkUI"
            ],
            path: "Tests/KitchenSinkTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
