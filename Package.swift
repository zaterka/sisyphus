// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sisyphus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SisyphusCore", targets: ["SisyphusCore"]),
        .executable(name: "Sisyphus", targets: ["Sisyphus"]),
    ],
    targets: [
        .target(name: "SisyphusCore"),
        .executableTarget(
            name: "Sisyphus",
            dependencies: ["SisyphusCore"]
        ),
        .testTarget(
            name: "SisyphusCoreTests",
            dependencies: ["SisyphusCore"]
        ),
    ]
)
