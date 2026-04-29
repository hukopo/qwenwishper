import Foundation
@preconcurrency import KeyboardShortcuts

enum HotkeyShortcutNames {
    static let toggleRecording = "toggleRecording"
}

final class HotkeyMonitor: HotkeyMonitoring {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private let shortcutName: KeyboardShortcuts.Name

    init(shortcutName: String = HotkeyShortcutNames.toggleRecording) {
        self.shortcutName = KeyboardShortcuts.Name(shortcutName)
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyDown(for: self.shortcutName) { [weak self] in
            self?.onPress?()
        }
        KeyboardShortcuts.onKeyUp(for: self.shortcutName) { [weak self] in
            self?.onRelease?()
        }
    }

    deinit {
        KeyboardShortcuts.removeAllHandlers()
    }

    func register(_ descriptor: HotkeyDescriptor) throws {
        KeyboardShortcuts.setShortcut(descriptor.keyboardShortcut, for: shortcutName)
    }

    func unregister() {
        KeyboardShortcuts.setShortcut(nil, for: shortcutName)
    }
}
