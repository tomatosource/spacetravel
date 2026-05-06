// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceTravel",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SpaceTravel",
            path: "Sources/SpaceTravel"
        )
    ]
)
