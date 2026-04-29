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
    static let defaultQwenModelID = "mlx-community/Qwen3-1.7B-4bit"

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
            title: "Qwen3 0.6B (Fast)",
            modelID: "mlx-community/Qwen3-0.6B-4bit",
            description: "Smallest fresh Qwen3 preset. Best latency for live translation.",
            recommendedFor: "Realtime translation on smaller Macs",
            estimatedSizeLabel: "~335 MB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen3 1.7B (Recommended)",
            modelID: "mlx-community/Qwen3-1.7B-4bit",
            description: "Better multilingual translation and rewrite quality with still-local latency.",
            recommendedFor: "Balanced live translation and dictation cleanup",
            estimatedSizeLabel: "~930 MB"
        ),
        ModelPreset(
            kind: .qwen,
            title: "Qwen3.5 2B",
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            description: "Still available as a heavier custom-quality option for rewrite-focused use.",
            recommendedFor: "Higher quality rewrite when realtime latency matters less",
            estimatedSizeLabel: "~1.2 GB"
        ),
    ]
}
