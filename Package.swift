// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InstallModel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "InstallModel", targets: ["InstallModelApp"])
    ],
    targets: [
        .executableTarget(
            name: "InstallModelApp",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "InstallModelAppTests",
            dependencies: ["InstallModelApp"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
