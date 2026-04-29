import Foundation

enum RewriteMode: String, Codable, Sendable {
    case aggressive
}

enum AudioInputSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            "Microphone"
        case .systemAudio:
            "System Audio"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            "Live translation from your current mic input"
        case .systemAudio:
            "Live translation from audio currently playing on this Mac"
        }
    }
}

enum TranslationTargetLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case english
    case russian
    case german
    case spanish
    case french
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            "English"
        case .russian:
            "Russian"
        case .german:
            "German"
        case .spanish:
            "Spanish"
        case .french:
            "French"
        case .japanese:
            "Japanese"
        }
    }

    var promptName: String {
        title
    }

    var usesWhisperNativeTranslation: Bool {
        self == .english
    }
}

struct TranscriptionResultPayload: Sendable, Equatable {
    var text: String
    var latency: Duration
    var audioURL: URL
}

struct RewriteResultPayload: Sendable, Equatable {
    var sourceText: String
    var rewrittenText: String
    var latency: Duration
}

struct InsertResult: Sendable, Equatable {
    enum Method: String, Sendable {
        case accessibility
        case clipboardFallback
    }

    var method: Method
}

struct DictationSnapshot: Sendable, Equatable {
    var sourceText: String
    var rewrittenText: String
    var insertMethod: InsertResult.Method
    var finishedAt: Date
}

struct LiveTranslationSnapshot: Sendable, Equatable {
    var transcriptText: String
    var translatedText: String
    var finishedAt: Date
}

struct DiagnosticsEntry: Identifiable, Sendable, Equatable {
    enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let level: Level
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

enum PipelineStatus: Equatable {
    case idle
    case checkingPermissions
    case loadingModels
    case recording
    case liveCapturing
    case transcribing
    case liveTranscribing
    case rewriting
    case liveTranslating
    case pasting
    case error(String)

    var label: String {
        switch self {
        case .idle:
            "Idle"
        case .checkingPermissions:
            "Checking permissions"
        case .loadingModels:
            "Loading models"
        case .recording:
            "Recording"
        case .liveCapturing:
            "Capturing live audio"
        case .transcribing:
            "Transcribing"
        case .liveTranscribing:
            "Live transcription"
        case .rewriting:
            "Rewriting"
        case .liveTranslating:
            "Live translation"
        case .pasting:
            "Pasting"
        case .error(let message):
            "Error: \(message)"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "mic"
        case .checkingPermissions, .loadingModels:
            "arrow.triangle.2.circlepath"
        case .recording, .liveCapturing:
            "waveform.circle.fill"
        case .transcribing, .liveTranscribing:
            "captions.bubble"
        case .rewriting, .liveTranslating:
            "text.redaction"
        case .pasting:
            "doc.on.clipboard"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }
}

enum AppFailure: LocalizedError, Equatable {
    case microphoneDenied
    case screenCaptureDenied
    case accessibilityDenied
    case alreadyBusy
    case recordingNotActive
    case liveTranslationNotActive
    case emptySpeech
    case modelDownloadFailed(String)
    case transcriptionFailed(String)
    case rewriteFailed(String)
    case translationFailed(String)
    case pasteFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required."
        case .screenCaptureDenied:
            "Screen Recording access is required for system-audio capture."
        case .accessibilityDenied:
            "Accessibility access is required for text insertion."
        case .alreadyBusy:
            "The dictation pipeline is already processing another request."
        case .recordingNotActive:
            "Recording is not active."
        case .liveTranslationNotActive:
            "Live translation is not active."
        case .emptySpeech:
            "No speech was detected."
        case .modelDownloadFailed(let message):
            "Model download failed: \(message)"
        case .transcriptionFailed(let message):
            "Transcription failed: \(message)"
        case .rewriteFailed(let message):
            "Rewrite failed: \(message)"
        case .translationFailed(let message):
            "Translation failed: \(message)"
        case .pasteFailed(let message):
            "Paste failed: \(message)"
        }
    }
}
