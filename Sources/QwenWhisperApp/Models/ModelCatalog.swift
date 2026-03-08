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
    static let defaultQwenModelID = "mlx-community/Qwen3.5-2B-4bit"

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
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 0.8B",
            modelID: "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
            description: "Fastest rewrite, weakest editing quality.",
            recommendedFor: "Quick edits on short dictations",
            estimatedSizeLabel: "~450 MB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 2B (Recommended)",
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            description: "Best balance of speed and editing quality.",
            recommendedFor: "Everyday post-editing of Russian dictation",
            estimatedSizeLabel: "~1.2 GB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 4B",
            modelID: "mlx-community/Qwen3.5-4B-4bit",
            description: "Best editing quality. Higher RAM and latency.",
            recommendedFor: "Best quality when speed is not critical",
            estimatedSizeLabel: "~2.3 GB"
        ),
    ]
}
