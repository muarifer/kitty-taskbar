// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KittyTaskbar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "KittyTaskbar", path: "Sources/KittyTaskbar"),
        .testTarget(name: "KittyTaskbarTests", dependencies: ["KittyTaskbar"]),
    ]
)
