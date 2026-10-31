// swift-tools-version:5.9
import PackageDescription

// Ding's UI-free libraries: DingCore (logic), DingIPC (the socket between the app and its helper) and DingMCP
// (the MCP server). The app and the bundled helper (see project.yml) depend on these.
let package = Package(
    name: "DingCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DingCore", targets: ["DingCore"]),
        .library(name: "DingIPC", targets: ["DingIPC"]),
        .library(name: "DingMCP", targets: ["DingMCP"]),
    ],
    targets: [
        .target(name: "DingCore"),
        .target(name: "DingIPC"),
        .target(name: "DingMCP", dependencies: ["DingIPC"]),
        .testTarget(name: "DingCoreTests", dependencies: ["DingCore"]),
        .testTarget(name: "DingIPCTests", dependencies: ["DingIPC"]),
        .testTarget(name: "DingMCPTests", dependencies: ["DingMCP", "DingIPC"]),
    ]
)
