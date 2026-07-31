// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "enetforward",
    platforms: [
        // MenuBarExtra (the menu-bar app) requires macOS 13. The CLI and core
        // work on macOS 11+, but the whole package builds against 13 for simplicity.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "enetforward", targets: ["enetforward"]),
        .executable(name: "enetforwardapp", targets: ["enetforwardapp"]),
        .library(name: "ENETForwardCore", targets: ["ENETForwardCore"]),
    ],
    targets: [
        // Reusable relay engine shared by the CLI and the menu-bar app.
        .target(
            name: "ENETForwardCore",
            path: "Sources/ENETForwardCore"
        ),
        // Command-line forwarder.
        .executableTarget(
            name: "enetforward",
            dependencies: ["ENETForwardCore"],
            path: "Sources/enetforward"
        ),
        // SwiftUI menu-bar app.
        .executableTarget(
            name: "enetforwardapp",
            dependencies: ["ENETForwardCore"],
            path: "Sources/enetforwardapp"
        ),
    ]
)
