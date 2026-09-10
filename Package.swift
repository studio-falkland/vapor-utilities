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
        .library(name: "FileStorage", targets: ["FileStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.57.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.36.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
        .package(url: "https://github.com/pgvector/pgvector-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "VaporUtilities",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
            ]
        ),
        .target(
            name: "FluentPGVector",
            dependencies: [
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "Pgvector", package: "pgvector-swift"),
                .product(name: "PgvectorNIO", package: "pgvector-swift"),
            ]
        ),
        .testTarget(
            name: "VaporUtilitiesTests",
            dependencies: [
                "VaporUtilities",
                .product(name: "XCTFluent", package: "fluent-kit"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "SQLKit", package: "sql-kit"),
            ]
        ),
        .target(
            name: "FileStorage",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "FileStorageTests",
            dependencies: [
                "FileStorage",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SotoS3", package: "soto"),
            ]
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