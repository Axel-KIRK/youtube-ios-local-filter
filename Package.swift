// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalFilter",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LocalFilterCore", targets: ["LocalFilterCore"]),
               .executable(name: "local-filter-check", targets: ["LocalFilterCheck"])],
    targets: [
        .target(name: "CLocalCompression", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "LocalFilterCore", dependencies: ["CLocalCompression"]),
        .executableTarget(name: "LocalFilterCheck", dependencies: ["LocalFilterCore"]),
        .testTarget(name: "LocalFilterCoreTests", dependencies: ["LocalFilterCore"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
