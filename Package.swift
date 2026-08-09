// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SectorEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SectorEngine", targets: ["SectorEngine"]),
        .executable(name: "SectorEngineServer", targets: ["SectorEngineServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "SectorEngine", path: "Sources/SectorEngine"),
        .executableTarget(
            name: "SectorEngineServer",
            dependencies: [
                "SectorEngine",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/SectorEngineServer"),
        .testTarget(name: "SectorEngineTests", dependencies: ["SectorEngine"], path: "Tests/SectorEngineTests"),
    ]
)
