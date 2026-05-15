// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gander",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GanderApp",
            path: "Sources/Gander"
        ),
        .executableTarget(
            name: "gander",
            path: "Sources/gander-cli"
        ),
    ]
)
