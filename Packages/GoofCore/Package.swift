// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoofCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GoofCore", targets: ["GoofCore"]),
    ],
    targets: [
        .target(name: "GoofCore"),
        .testTarget(name: "GoofCoreTests", dependencies: ["GoofCore"]),
    ]
)
