// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PRadar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PRadar"),
        .testTarget(name: "PRadarTests", dependencies: ["PRadar"]),
    ]
)
