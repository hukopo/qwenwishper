import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Picker("Hotkey", selection: hotkeyBinding) {
                ForEach(HotkeyDescriptor.Preset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { controller.settings.launchAtLogin },
                set: { controller.settings.launchAtLogin = $0; controller.saveSettings() }
            ))

            Toggle("Enable logging", isOn: Binding(
                get: { controller.settings.loggingEnabled },
                set: { controller.settings.loggingEnabled = $0; controller.saveSettings() }
            ))

            Stepper(
                "Paste delay: \(controller.settings.pasteDelayMs) ms",
                value: Binding(
                    get: { controller.settings.pasteDelayMs },
                    set: { controller.settings.pasteDelayMs = $0; controller.saveSettings() }
                ),
                in: 0...1000,
                step: 20
            )

            Stepper(
                "Max recording: \(controller.settings.maxRecordingSeconds) s",
                value: Binding(
                    get: { controller.settings.maxRecordingSeconds },
                    set: { controller.settings.maxRecordingSeconds = $0; controller.saveSettings() }
                ),
                in: 5...120
            )

            TextField("Whisper model", text: Binding(
                get: { controller.settings.whisperModelID },
                set: { controller.settings.whisperModelID = $0; controller.saveSettings() }
            ))

            TextField("Qwen model", text: Binding(
                get: { controller.settings.qwenModelID },
                set: { controller.settings.qwenModelID = $0; controller.saveSettings() }
            ))

            HStack {
                Button("Prompt Accessibility") {
                    controller.refreshPermissions(promptForAccessibility: true)
                }
                Button("Reset Models", role: .destructive) {
                    controller.resetModels()
                }
            }
        }
        .padding(16)
    }

    private var hotkeyBinding: Binding<HotkeyDescriptor.Preset> {
        Binding(
            get: {
                HotkeyDescriptor.Preset.allCases.first(where: { $0.descriptor == controller.settings.hotkey }) ?? .commandShiftSpace
            },
            set: {
                controller.settings.hotkey = $0.descriptor
                controller.saveSettings()
            }
        )
    }
}
