// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vapor-utilities",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VaporUtilities", targets: ["VaporUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "VaporUtilities",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "VaporUtilitiesTests",
            dependencies: ["VaporUtilities"]
        ),
    ]
)
