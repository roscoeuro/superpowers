// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "enetforward",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "enetforward",
            path: "Sources/enetforward"
        )
    ]
)
