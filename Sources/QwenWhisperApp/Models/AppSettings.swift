import Carbon
import Foundation

struct HotkeyDescriptor: Codable, Equatable, Sendable {
    enum Preset: String, CaseIterable, Codable, Identifiable, Sendable {
        case commandShiftSpace
        case controlOptionSpace
        case rightOption

        var id: String { rawValue }

        var title: String {
            switch self {
            case .commandShiftSpace:
                "Command + Shift + Space"
            case .controlOptionSpace:
                "Control + Option + Space"
            case .rightOption:
                "Right Option"
            }
        }

        var descriptor: HotkeyDescriptor {
            switch self {
            case .commandShiftSpace:
                HotkeyDescriptor(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))
            case .controlOptionSpace:
                HotkeyDescriptor(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))
            case .rightOption:
                HotkeyDescriptor(keyCode: UInt32(kVK_RightOption), carbonModifiers: UInt32(0))
            }
        }
    }

    var keyCode: UInt32
    var carbonModifiers: UInt32

    var readableName: String {
        if let preset = Preset.allCases.first(where: { $0.descriptor == self }) {
            return preset.title
        }

        return "Key code \(keyCode)"
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let defaults = AppSettings(
        hotkey: HotkeyDescriptor.Preset.commandShiftSpace.descriptor,
        launchAtLogin: false,
        didPromptLaunchAtLogin: false,
        pasteDelayMs: 120,
        maxRecordingSeconds: 30,
        whisperModelID: ModelCatalog.defaultWhisperModelID,
        qwenModelID: ModelCatalog.defaultQwenModelID,
        qwenEnabled: true,
        loggingEnabled: true,
        qwenSystemPrompt: ""
    )

    var hotkey: HotkeyDescriptor
    var launchAtLogin: Bool
    var didPromptLaunchAtLogin: Bool
    var pasteDelayMs: Int
    var maxRecordingSeconds: Int
    var whisperModelID: String
    var qwenModelID: String
    /// When false the Qwen rewrite step is skipped entirely; Whisper text is pasted as-is.
    var qwenEnabled: Bool
    var loggingEnabled: Bool
    var qwenSystemPrompt: String

    init(
        hotkey: HotkeyDescriptor,
        launchAtLogin: Bool,
        didPromptLaunchAtLogin: Bool,
        pasteDelayMs: Int,
        maxRecordingSeconds: Int,
        whisperModelID: String,
        qwenModelID: String,
        qwenEnabled: Bool,
        loggingEnabled: Bool,
        qwenSystemPrompt: String
    ) {
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
        self.didPromptLaunchAtLogin = didPromptLaunchAtLogin
        self.pasteDelayMs = pasteDelayMs
        self.maxRecordingSeconds = maxRecordingSeconds
        self.whisperModelID = whisperModelID
        self.qwenModelID = qwenModelID
        self.qwenEnabled = qwenEnabled
        self.loggingEnabled = loggingEnabled
        self.qwenSystemPrompt = qwenSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decode(HotkeyDescriptor.self, forKey: .hotkey)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        didPromptLaunchAtLogin = try container.decode(Bool.self, forKey: .didPromptLaunchAtLogin)
        pasteDelayMs = try container.decode(Int.self, forKey: .pasteDelayMs)
        maxRecordingSeconds = try container.decode(Int.self, forKey: .maxRecordingSeconds)
        whisperModelID = try container.decode(String.self, forKey: .whisperModelID)
        qwenModelID = try container.decode(String.self, forKey: .qwenModelID)
        // Default true — old settings files without this key keep Qwen enabled.
        qwenEnabled = (try? container.decode(Bool.self, forKey: .qwenEnabled)) ?? true
        loggingEnabled = try container.decode(Bool.self, forKey: .loggingEnabled)
        qwenSystemPrompt = (try? container.decode(String.self, forKey: .qwenSystemPrompt)) ?? ""
    }
}

final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app_settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
