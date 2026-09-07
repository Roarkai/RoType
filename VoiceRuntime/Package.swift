// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoTypeVoiceRuntime",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RoTypeVoiceWorker", targets: ["RoTypeVoiceWorker"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git",
                 revision: "bf14ae0c26e4e85553dd989571cae29d70fa6735"),
    ],
    targets: [
        .executableTarget(name: "RoTypeVoiceWorker", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
            .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        ]),
    ]
)
