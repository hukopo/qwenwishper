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
        pasteDelayMs: 120,
        maxRecordingSeconds: 30,
        whisperModelID: "base",
        qwenModelID: "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
        loggingEnabled: true
    )

    var hotkey: HotkeyDescriptor
    var launchAtLogin: Bool
    var pasteDelayMs: Int
    var maxRecordingSeconds: Int
    var whisperModelID: String
    var qwenModelID: String
    var loggingEnabled: Bool
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
