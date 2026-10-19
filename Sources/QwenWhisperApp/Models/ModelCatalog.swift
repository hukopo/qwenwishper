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
    static let defaultQwenModelID = "mlx-community/Qwen3.5-0.8B-4bit"

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
    ]

    static let qwenPresets: [ModelPreset] = [
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 0.8B (Recommended)",
            modelID: "mlx-community/Qwen3.5-0.8B-4bit",
            description: "Small and fast. Good enough for cleanup and live translation.",
            recommendedFor: "Everyday dictation and live translation",
            estimatedSizeLabel: "~620 MB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 2B",
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            description: "Better quality, a bit slower.",
            recommendedFor: "Rewrite quality over speed",
            estimatedSizeLabel: "~1.7 GB"
        ),
    ]
}
