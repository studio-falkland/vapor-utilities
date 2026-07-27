// swift-tools-version: 6.0
// Dev-only package — not referenced by the main Package.swift.
// Run documentation generation from this directory:
//
//   cd Documentation
//   swift package generate-documentation --target VaporUtilities
//   swift package preview-documentation --target VaporUtilities
//
import PackageDescription

let package = Package(
    name: "vapor-utilities-docs",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(name: "vapor-utilities", path: ".."),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "vapor-utilities-docs",
            dependencies: [
                .product(name: "VaporUtilities", package: "vapor-utilities"),
            ]
        ),
    ]
)