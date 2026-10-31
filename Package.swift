// swift-tools-version:5.9
import PackageDescription

// Pure, UI-free logic for Ding. The app target (see project.yml) depends on this.
let package = Package(
    name: "DingCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DingCore", targets: ["DingCore"]),
    ],
    targets: [
        .target(name: "DingCore"),
        .testTarget(name: "DingCoreTests", dependencies: ["DingCore"]),
    ]
)
