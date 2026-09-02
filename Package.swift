// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RoType",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RoTypeVoice", targets: ["RoTypeVoice"]),
        .library(name: "RoTypeVoiceCore", targets: ["RoTypeVoiceCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.1.0"
        ),
    ],
    targets: [
        .target(
            name: "RoTypeVoiceCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .executableTarget(
            name: "RoTypeVoice",
            dependencies: ["RoTypeVoiceCore"]
        ),
        .testTarget(
            name: "RoTypeVoiceCoreTests",
            dependencies: ["RoTypeVoiceCore"]
        ),
    ]
)
