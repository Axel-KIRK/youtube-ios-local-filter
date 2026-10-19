// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalFilter",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LocalFilterCore", targets: ["LocalFilterCore"]),
               .library(name: "LocalFilterTransport", targets: ["LocalFilterTransport"]),
               .library(name: "LocalFilterSetup", targets: ["LocalFilterSetup"]),
               .executable(name: "local-filter-proxy", targets: ["LocalFilterProxy"]),
               .executable(name: "local-filter-check", targets: ["LocalFilterCheck"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0")
    ],
    targets: [
        .target(name: "CLocalCompression", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "LocalFilterCore", dependencies: ["CLocalCompression"]),
        .target(name: "LocalFilterSetup"),
        .executableTarget(name: "LocalFilterCheck", dependencies: ["LocalFilterCore"]),
        .target(name: "LocalFilterTransport", dependencies: ["LocalFilterCore", "CLocalCompression",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "X509", package: "swift-certificates")]),
        .executableTarget(name: "LocalFilterProxy", dependencies: ["LocalFilterTransport"]),
        .testTarget(name: "LocalFilterCoreTests", dependencies: ["LocalFilterCore"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "LocalFilterTransportTests", dependencies: ["LocalFilterTransport", "LocalFilterCore", "LocalFilterSetup",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl")])
    ],
    swiftLanguageModes: [.v5]
)
