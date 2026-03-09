import Foundation

struct ModelPreset: Identifiable, Equatable {
    enum Kind { case whisper, qwen }

    let kind: Kind
    let title: String
    let modelID: String
    let description: String
    let recommendedFor: String
    let estimatedSizeLabel: String

    var id: String { modelID }
}

enum ModelCatalog {
    static let defaultWhisperModelID = "small"
    // Qwen2.5-Instruct uses model_type "qwen2" — supported by MLXLLM 2.30+.
    // Qwen3.5 (model_type "qwen3_5") is NOT registered in MLXLLM and throws
    // "Unsupported model type: qwen3_5" on every call, preventing the container
    // from ever being cached and causing a full 13-second reload on every recording.
    static let defaultQwenModelID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    static let whisperPresets: [ModelPreset] = [
        ModelPreset(
            kind: .whisper,
            title: "Base",
            modelID: "base",
            description: "Fastest and smallest. Weaker accuracy for Russian.",
            recommendedFor: "Low-latency dictation in quiet conditions",
            estimatedSizeLabel: "~75 MB"
        ),
        ModelPreset(
            kind: .whisper,
            title: "Small (Recommended)",
            modelID: "small",
            description: "Balanced speed and accuracy. Recommended for Russian dictation.",
            recommendedFor: "Everyday Russian dictation",
            estimatedSizeLabel: "~240 MB"
        ),
        ModelPreset(
            kind: .whisper,
            title: "Medium",
            modelID: "medium",
            description: "Highest local quality. Slower and uses more RAM.",
            recommendedFor: "Maximum transcription accuracy",
            estimatedSizeLabel: "~750 MB"
        ),
    ]

    static let qwenPresets: [ModelPreset] = [
        // Qwen2.5 — model_type "qwen2", fully supported by current MLXLLM, no thinking mode.
        ModelPreset(
            kind: .qwen,
            title: "Qwen2.5 0.5B (Fast)",
            modelID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            description: "Smallest and fastest. Acceptable editing quality.",
            recommendedFor: "Quick edits, low-latency dictation",
            estimatedSizeLabel: "~400 MB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen2.5 1.5B (Recommended)",
            modelID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            description: "Best balance of speed and editing quality.",
            recommendedFor: "Everyday Russian dictation",
            estimatedSizeLabel: "~1 GB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen2.5 3B",
            modelID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            description: "Higher quality rewrites. More RAM and slightly slower.",
            recommendedFor: "Best quality when latency is not critical",
            estimatedSizeLabel: "~1.9 GB"
        ),
    ]
}
