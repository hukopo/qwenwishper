import Carbon
import Foundation
@preconcurrency import KeyboardShortcuts

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

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(shortcut: KeyboardShortcuts.Shortcut) {
        self.init(
            keyCode: UInt32(shortcut.carbonKeyCode),
            carbonModifiers: UInt32(shortcut.carbonModifiers)
        )
    }

    var keyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            carbonKeyCode: Int(keyCode),
            carbonModifiers: Int(carbonModifiers)
        )
    }

    var readableName: String {
        keyboardShortcut.description
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    static let defaults = AppSettings(
        hotkey: HotkeyDescriptor.Preset.commandShiftSpace.descriptor,
        launchAtLogin: false,
        didPromptLaunchAtLogin: false,
        pasteDelayMs: 120,
        maxRecordingSeconds: 30,
        liveAudioSource: .microphone,
        liveTranslationTargetLanguage: .english,
        liveTranslationIntervalMs: 1_200,
        whisperModelID: ModelCatalog.defaultWhisperModelID,
        qwenModelID: ModelCatalog.defaultQwenModelID,
        qwenEnabled: true,
        loggingEnabled: true,
        promptPresets: RewritePromptBuilder.defaultPresets,
        selectedPresetID: RewritePromptBuilder.defaultPresetID
    )

    var hotkey: HotkeyDescriptor
    var launchAtLogin: Bool
    var didPromptLaunchAtLogin: Bool
    var pasteDelayMs: Int
    var maxRecordingSeconds: Int
    var liveAudioSource: AudioInputSource
    var liveTranslationTargetLanguage: TranslationTargetLanguage
    var liveTranslationIntervalMs: Int
    var whisperModelID: String
    var qwenModelID: String
    /// When false the Qwen rewrite step is skipped entirely; Whisper text is pasted as-is.
    var qwenEnabled: Bool
    var loggingEnabled: Bool
    var promptPresets: [PromptPreset]
    var selectedPresetID: String

    /// The active system prompt resolved from the selected preset.
    var qwenSystemPrompt: String {
        promptPresets.first(where: { $0.id == selectedPresetID })?.prompt
            ?? RewritePromptBuilder.defaultSystemPrompt
    }

    init(
        hotkey: HotkeyDescriptor,
        launchAtLogin: Bool,
        didPromptLaunchAtLogin: Bool,
        pasteDelayMs: Int,
        maxRecordingSeconds: Int,
        liveAudioSource: AudioInputSource,
        liveTranslationTargetLanguage: TranslationTargetLanguage,
        liveTranslationIntervalMs: Int,
        whisperModelID: String,
        qwenModelID: String,
        qwenEnabled: Bool,
        loggingEnabled: Bool,
        promptPresets: [PromptPreset],
        selectedPresetID: String
    ) {
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
        self.didPromptLaunchAtLogin = didPromptLaunchAtLogin
        self.pasteDelayMs = pasteDelayMs
        self.maxRecordingSeconds = maxRecordingSeconds
        self.liveAudioSource = liveAudioSource
        self.liveTranslationTargetLanguage = liveTranslationTargetLanguage
        self.liveTranslationIntervalMs = liveTranslationIntervalMs
        self.whisperModelID = whisperModelID
        self.qwenModelID = qwenModelID
        self.qwenEnabled = qwenEnabled
        self.loggingEnabled = loggingEnabled
        self.promptPresets = promptPresets
        self.selectedPresetID = selectedPresetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decode(HotkeyDescriptor.self, forKey: .hotkey)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        didPromptLaunchAtLogin = try container.decode(Bool.self, forKey: .didPromptLaunchAtLogin)
        pasteDelayMs = try container.decode(Int.self, forKey: .pasteDelayMs)
        maxRecordingSeconds = try container.decode(Int.self, forKey: .maxRecordingSeconds)
        liveAudioSource = (try? container.decode(AudioInputSource.self, forKey: .liveAudioSource)) ?? .microphone
        liveTranslationTargetLanguage = (try? container.decode(
            TranslationTargetLanguage.self,
            forKey: .liveTranslationTargetLanguage
        )) ?? .english
        liveTranslationIntervalMs = (try? container.decode(Int.self, forKey: .liveTranslationIntervalMs)) ?? 1_200
        whisperModelID = try container.decode(String.self, forKey: .whisperModelID)
        qwenModelID = try container.decode(String.self, forKey: .qwenModelID)
        // Default true — old settings files without this key keep Qwen enabled.
        qwenEnabled = (try? container.decode(Bool.self, forKey: .qwenEnabled)) ?? true
        loggingEnabled = try container.decode(Bool.self, forKey: .loggingEnabled)

        // Migration: old settings had a single qwenSystemPrompt string.
        if let presets = try? container.decode([PromptPreset].self, forKey: .promptPresets),
           !presets.isEmpty {
            promptPresets = presets
        } else {
            var presets = RewritePromptBuilder.defaultPresets
            // If the user had a custom prompt, preserve it in the editor preset.
            if let oldPrompt = try? container.decode(String.self, forKey: .legacyQwenSystemPrompt),
               !oldPrompt.isEmpty, oldPrompt != RewritePromptBuilder.defaultSystemPrompt {
                if let idx = presets.firstIndex(where: { $0.id == RewritePromptBuilder.defaultPresetID }) {
                    presets[idx].prompt = oldPrompt
                }
            }
            promptPresets = presets
        }
        selectedPresetID = (try? container.decode(String.self, forKey: .selectedPresetID))
            ?? RewritePromptBuilder.defaultPresetID
        normalizePromptPresets()
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey, launchAtLogin, didPromptLaunchAtLogin, pasteDelayMs, maxRecordingSeconds
        case liveAudioSource, liveTranslationTargetLanguage, liveTranslationIntervalMs
        case whisperModelID, qwenModelID, qwenEnabled, loggingEnabled
        case promptPresets, selectedPresetID
        case legacyQwenSystemPrompt = "qwenSystemPrompt"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(didPromptLaunchAtLogin, forKey: .didPromptLaunchAtLogin)
        try container.encode(pasteDelayMs, forKey: .pasteDelayMs)
        try container.encode(maxRecordingSeconds, forKey: .maxRecordingSeconds)
        try container.encode(liveAudioSource, forKey: .liveAudioSource)
        try container.encode(liveTranslationTargetLanguage, forKey: .liveTranslationTargetLanguage)
        try container.encode(liveTranslationIntervalMs, forKey: .liveTranslationIntervalMs)
        try container.encode(whisperModelID, forKey: .whisperModelID)
        try container.encode(qwenModelID, forKey: .qwenModelID)
        try container.encode(qwenEnabled, forKey: .qwenEnabled)
        try container.encode(loggingEnabled, forKey: .loggingEnabled)
        try container.encode(promptPresets, forKey: .promptPresets)
        try container.encode(selectedPresetID, forKey: .selectedPresetID)
    }

    mutating func normalizePromptPresets() {
        liveTranslationIntervalMs = max(600, min(3_000, liveTranslationIntervalMs))

        if promptPresets.isEmpty {
            promptPresets = RewritePromptBuilder.defaultPresets
        }

        if !promptPresets.contains(where: { $0.id == selectedPresetID }) {
            selectedPresetID = promptPresets.first?.id ?? RewritePromptBuilder.defaultPresetID
        }
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
