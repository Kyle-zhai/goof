// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KuroCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KuroCore", targets: ["KuroCore"]),
    ],
    targets: [
        .target(name: "KuroCore"),
        .testTarget(name: "KuroCoreTests", dependencies: ["KuroCore"]),
    ]
)
