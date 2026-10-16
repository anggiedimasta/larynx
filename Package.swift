// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Larynx",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Larynx",
            path: "Sources/Larynx"
        ),
        .testTarget(
            name: "LarynxTests",
            dependencies: ["Larynx"],
            path: "Tests/LarynxTests"
        )
    ]
)
