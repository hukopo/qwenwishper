// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "qwenwhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "QwenWhisperApp",
            targets: ["QwenWhisperApp"]
        ),
        .executable(
            name: "WhisperProbe",
            targets: ["WhisperProbe"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.30.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.9")),
        .package(url: "https://github.com/apple/swift-testing", from: "6.0.3"),
    ],
    targets: [
        .executableTarget(
            name: "QwenWhisperApp",
            dependencies: [
                "WhisperBridge",
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),
        .target(
            name: "WhisperBridge",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .executableTarget(
            name: "WhisperProbe",
            dependencies: [
                "WhisperBridge"
            ]
        ),
        .testTarget(
            name: "QwenWhisperAppTests",
            dependencies: [
                "QwenWhisperApp",
                .product(name: "Testing", package: "swift-testing"),
            ]
        )
    ]
)
