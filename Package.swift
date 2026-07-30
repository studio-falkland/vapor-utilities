// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vapor-utilities",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VaporUtilities", targets: ["VaporUtilities"]),
        .library(name: "FluentPGVector", targets: ["FluentPGVector"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.57.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.36.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "VaporUtilities",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .target(
            name: "FluentPGVector",
            dependencies: [
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
            ]
        ),
        .testTarget(
            name: "VaporUtilitiesTests",
            dependencies: ["VaporUtilities"]
        ),
        .testTarget(
            name: "FluentPGVectorTests",
            dependencies: [
                "FluentPGVector",
                .product(name: "XCTFluent", package: "fluent-kit"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ]
)