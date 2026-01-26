// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacMicMute",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "MacMicMute",
            path: "Sources"
        )
    ]
)
