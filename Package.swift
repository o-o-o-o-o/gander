// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UrBrowse",
    platforms: [.macOS(.v14)],
    products: [
        // Shared ur skeleton (pots, addressed requests, socket IPC, generic CLI). Other ur apps
        // (ur-mail, ur-notes) depend on this product.
        .library(name: "UrKit", targets: ["UrKit"]),
    ],
    targets: [
        .target(name: "UrKit", path: "Sources/UrKit"),
        .target(name: "UrBrowseSpec", dependencies: ["UrKit"], path: "Sources/UrBrowseSpec"),
        .executableTarget(
            name: "UrBrowseApp",
            dependencies: ["UrKit", "UrBrowseSpec"],
            path: "Sources/UrBrowse"
        ),
        .executableTarget(
            name: "ur-browse",
            dependencies: ["UrKit", "UrBrowseSpec"],
            path: "Sources/ur-browse-cli"
        ),
    ]
)
