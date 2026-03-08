import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        TabView {
            GeneralTab(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }

            ModelsStorageTab(controller: controller)
                .tabItem { Label("Models & Storage", systemImage: "internaldrive") }

            PromptTab(controller: controller)
                .tabItem { Label("Prompt", systemImage: "text.bubble") }
        }
        .frame(width: 520)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
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

            Button("Prompt Accessibility") {
                controller.refreshPermissions(promptForAccessibility: true)
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

// MARK: - Models & Storage Tab

private struct ModelsStorageTab: View {
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModelPickerSection(
                    label: "Whisper Model",
                    presets: ModelCatalog.whisperPresets,
                    modelID: Binding(
                        get: { controller.settings.whisperModelID },
                        set: { controller.settings.whisperModelID = $0; controller.saveSettings() }
                    )
                )

                Divider()

                ModelPickerSection(
                    label: "Qwen Model",
                    presets: ModelCatalog.qwenPresets,
                    modelID: Binding(
                        get: { controller.settings.qwenModelID },
                        set: { controller.settings.qwenModelID = $0; controller.saveSettings() }
                    )
                )

                Divider()

                StorageSection(controller: controller)
            }
            .padding(16)
        }
    }
}

private struct ModelPickerSection: View {
    let label: String
    let presets: [ModelPreset]
    @Binding var modelID: String

    private var selectedPresetID: String {
        presets.first(where: { $0.modelID == modelID })?.modelID ?? "custom"
    }

    private var selectedPreset: ModelPreset? {
        presets.first(where: { $0.modelID == modelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)

            Picker(label, selection: Binding(
                get: { selectedPresetID },
                set: { newID in
                    if newID != "custom" {
                        modelID = newID
                    }
                }
            )) {
                ForEach(presets) { preset in
                    Text(preset.title).tag(preset.modelID)
                }
                Text("Custom…").tag("custom")
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if selectedPresetID == "custom" {
                TextField("Model ID", text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else if let preset = selectedPreset {
                Text(preset.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Best for: \(preset.recommendedFor)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preset.estimatedSizeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct StorageSection: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage")
                .font(.headline)

            StorageRow(
                title: "App",
                url: controller.storageSnapshot.appURL,
                sizeBytes: controller.storageSnapshot.appSizeBytes
            )
            StorageRow(
                title: "Models",
                url: controller.storageSnapshot.modelsURL,
                sizeBytes: controller.storageSnapshot.modelsSizeBytes
            )
            StorageRow(
                title: "Recordings",
                url: controller.storageSnapshot.recordingsURL,
                sizeBytes: controller.storageSnapshot.recordingsSizeBytes
            )

            HStack(spacing: 8) {
                Button("Open Models Folder") { controller.openModelsFolder() }
                Button("Open Recordings Folder") { controller.openRecordingsFolder() }
                Button("Reveal App in Finder") { controller.revealAppInFinder() }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button("Clear Models", role: .destructive) { controller.clearModels() }
                Button("Clear Recordings", role: .destructive) { controller.clearRecordings() }
            }
        }
    }
}

private struct StorageRow: View {
    let title: String
    let url: URL
    let sizeBytes: Int64

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(abbreviatedPath(url))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(sizeBytes > 0 ? sizeBytes.humanReadableFileSize : "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Prompt Tab

private struct PromptTab: View {
    @ObservedObject var controller: AppController

    private var isDefault: Bool {
        controller.settings.qwenSystemPrompt == RewritePromptBuilder.defaultSystemPrompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Qwen Post-Processing System Prompt")
                    .font(.headline)
                Text("Инструкция, которую получает Qwen перед редактурой транскрипта. Изменения сохраняются автоматически.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: Binding(
                get: { controller.settings.qwenSystemPrompt },
                set: { controller.settings.qwenSystemPrompt = $0; controller.saveSettings() }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            HStack {
                Text("\(controller.settings.qwenSystemPrompt.count) символов\(isDefault ? " · по умолчанию" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Сбросить") {
                    controller.resetQwenPrompt()
                }
                .disabled(isDefault)
            }
        }
        .padding(16)
    }
}
