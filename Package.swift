// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowOpsCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "SnowOpsCore", targets: ["SnowOpsCore"])],
    targets: [
        .target(name: "SnowOpsCore"),
        .testTarget(name: "SnowOpsCoreTests", dependencies: ["SnowOpsCore"])
    ]
)
