// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RoType",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RoTypeApp", targets: ["RoTypeApp"]),
        .executable(name: "RoTypeTranslationService", targets: ["RoTypeTranslationService"]),
        .library(name: "RoTypeCore", targets: ["RoTypeCore"]),
    ],
    targets: [
        .target(
            name: "RoTypeXPCProtocol",
            path: "Shared/RoTypeXPCProtocol",
            publicHeadersPath: "include"
        ),
        .target(name: "RoTypeCore"),
        .executableTarget(
            name: "RoTypeApp",
            dependencies: ["RoTypeCore", "RoTypeXPCProtocol"]
        ),
        .executableTarget(
            name: "RoTypeTranslationService",
            dependencies: ["RoTypeCore", "RoTypeXPCProtocol"]
        ),
        .testTarget(
            name: "RoTypeAppTests",
            dependencies: ["RoTypeApp"]
        ),
        .testTarget(
            name: "RoTypeCoreTests",
            dependencies: ["RoTypeCore"]
        ),
        .testTarget(
            name: "RoTypeTranslationServiceTests",
            dependencies: ["RoTypeCore", "RoTypeTranslationService"]
        ),
    ]
)
