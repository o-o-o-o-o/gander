// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UrBrowse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UrBrowseApp",
            path: "Sources/UrBrowse"
        ),
        .executableTarget(
            name: "ur-browse",
            path: "Sources/ur-browse-cli"
        ),
    ]
)
