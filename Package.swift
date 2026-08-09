// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SectorEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SectorEngine", targets: ["SectorEngine"]),
    ],
    targets: [
        .target(name: "SectorEngine", path: "Sources/SectorEngine"),
        .testTarget(name: "SectorEngineTests", dependencies: ["SectorEngine"], path: "Tests/SectorEngineTests"),
    ]
)
