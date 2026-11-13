// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HanKey",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HanKeyCore"),
        .executableTarget(name: "HanKey", dependencies: ["HanKeyCore"]),
        .testTarget(name: "HanKeyCoreTests", dependencies: ["HanKeyCore"]),
    ]
)
