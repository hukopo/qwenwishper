// swift-tools-version: 6.2

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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "1.15.0")),
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "1.0.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.5")),
    ],
    targets: [
        .executableTarget(
            name: "QwenWhisperApp",
            dependencies: [
                "WhisperBridge",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
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
        .testTarget(
            name: "QwenWhisperAppTests",
            dependencies: ["QwenWhisperApp"]
        )
    ]
)
