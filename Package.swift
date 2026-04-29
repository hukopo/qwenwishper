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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "1.15.0")),
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.30.6")),
        // Pinned to main-branch commit that adds qwen3_5 / Qwen35Model support.
        // Released versions ≤ 2.30.6 only know qwen2/qwen3 and throw
        // "Unsupported model type: qwen3_5" for Qwen3.5 models.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "6bb84aac13f76ca5e2c3ff312bc072977e684ff4"),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.9")),
        .package(url: "https://github.com/apple/swift-testing", from: "6.0.3"),
    ],
    targets: [
        .executableTarget(
            name: "QwenWhisperApp",
            dependencies: [
                "WhisperBridge",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
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
