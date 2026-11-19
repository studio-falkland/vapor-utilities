// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "vapor-utilities",
    platforms: [
        .macOS("26.2"),
    ],
    products: [
        .library(name: "VaporUtilities", targets: ["VaporUtilities"]),
        .library(name: "FluentPGVector", targets: ["FluentPGVector"]),
        .library(name: "FileStorage", targets: ["FileStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "5.0.0-beta.4"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.57.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.36.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.2"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.3"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
        .package(url: "https://github.com/pgvector/pgvector-swift.git", from: "0.1.0"),
        // 7.10.x emits `sdkId`, which requires an unreleased soto-core.
        .package(url: "https://github.com/soto-project/soto-codegenerator", "7.9.6"..<"7.10.0"),
        .package(url: "https://github.com/soto-project/soto-core.git", from: "7.13.0"),
    ],
    targets: [
        .target(
            name: "VaporUtilities",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQL", package: "fluent-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
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
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),
        .target(
            name: "FileStorage",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SotoCore", package: "soto-core"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            plugins: [
                .plugin(name: "SotoCodeGeneratorPlugin", package: "soto-codegenerator"),
            ]
        ),
        .testTarget(
            name: "FileStorageTests",
            dependencies: [
                "FileStorage",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "SotoCore", package: "soto-core"),
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
