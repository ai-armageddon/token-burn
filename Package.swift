// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenBurn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TokenBurn", resources: [.copy("ProviderLogos")]),
        .testTarget(name: "TokenBurnTests", dependencies: ["TokenBurn"])
    ]
)
