import Foundation

enum RewriteMode: String, Codable, Sendable {
    case aggressive
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
    case transcribing
    case rewriting
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
        case .transcribing:
            "Transcribing"
        case .rewriting:
            "Rewriting"
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
        case .recording:
            "waveform.circle.fill"
        case .transcribing:
            "captions.bubble"
        case .rewriting:
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
    case accessibilityDenied
    case alreadyBusy
    case recordingNotActive
    case emptySpeech
    case modelDownloadFailed(String)
    case transcriptionFailed(String)
    case rewriteFailed(String)
    case pasteFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required."
        case .accessibilityDenied:
            "Accessibility access is required for text insertion."
        case .alreadyBusy:
            "The dictation pipeline is already processing another request."
        case .recordingNotActive:
            "Recording is not active."
        case .emptySpeech:
            "No speech was detected."
        case .modelDownloadFailed(let message):
            "Model download failed: \(message)"
        case .transcriptionFailed(let message):
            "Transcription failed: \(message)"
        case .rewriteFailed(let message):
            "Rewrite failed: \(message)"
        case .pasteFailed(let message):
            "Paste failed: \(message)"
        }
    }
}
