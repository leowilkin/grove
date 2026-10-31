// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Grove",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Grove",
            path: "Sources/Grove"
        ),
        .testTarget(
            name: "GroveTests",
            dependencies: ["Grove"],
            path: "Tests/GroveTests"
        ),
    ]
)
