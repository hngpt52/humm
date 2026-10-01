// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Humm",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Humm", path: "Sources/Humm")
    ]
)
