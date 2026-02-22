// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CCMonitorCore",
            path: "Sources/CCMonitorCore"
        ),
        .executableTarget(
            name: "CCMonitor",
            dependencies: ["CCMonitorCore"],
            path: "Sources/CCMonitor"
        ),
        .executableTarget(
            name: "CCMonitorDoctor",
            dependencies: ["CCMonitorCore"],
            path: "Sources/CCMonitorDoctor"
        ),
        .executableTarget(
            name: "CCMonitorTests",
            dependencies: ["CCMonitorCore"],
            path: "Tests/CCMonitorTests"
        )
    ]
)
