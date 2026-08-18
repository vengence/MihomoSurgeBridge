// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MihomoSurgeBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MihomoSurgeBridgeCore", targets: ["MihomoSurgeBridgeCore"]),
        .executable(name: "MihomoSurgeBridge", targets: ["MihomoSurgeBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "MihomoSurgeBridgeCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "MihomoSurgeBridge",
            dependencies: ["MihomoSurgeBridgeCore"]
        ),
        .executableTarget(
            name: "MihomoSurgeBridgeSelfTest",
            dependencies: ["MihomoSurgeBridgeCore"],
            path: "Tests/SelfTest"
        )
    ]
)
