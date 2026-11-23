// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampusHub",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CampusHub",
            resources: [.copy("Resources/Appearance")]
        ),
        .testTarget(name: "CampusHubTests", dependencies: ["CampusHub"]),
    ]
)
