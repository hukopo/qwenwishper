import SwiftUI
@preconcurrency import KeyboardShortcuts

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
        .frame(minWidth: 560, idealWidth: 720, minHeight: 500, idealHeight: 720)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var controller: AppController

    var body: some View {
        let hotkeyName = KeyboardShortcuts.Name(HotkeyShortcutNames.toggleRecording)

        Form {
            KeyboardShortcuts.Recorder("Hotkey", name: hotkeyName) { shortcut in
                controller.settings.hotkey = HotkeyDescriptor(
                    shortcut: shortcut ?? AppSettings.defaults.hotkey.keyboardShortcut
                )
                controller.saveSettings()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Можно назначить любое сочетание. Конфликтующие системные шорткаты библиотека отсеивает автоматически.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset") {
                    controller.settings.hotkey = AppSettings.defaults.hotkey
                    controller.saveSettings()
                }
                .disabled(controller.settings.hotkey == AppSettings.defaults.hotkey)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { controller.settings.launchAtLogin },
                set: { controller.settings.launchAtLogin = $0; controller.saveSettings() }
            ))

            Toggle("Enable Qwen rewriting", isOn: Binding(
                get: { controller.settings.qwenEnabled },
                set: { controller.settings.qwenEnabled = $0; controller.saveSettings() }
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

            Section("Live Translation") {
                Picker("Audio source", selection: Binding(
                    get: { controller.settings.liveAudioSource },
                    set: { controller.settings.liveAudioSource = $0; controller.saveSettings() }
                )) {
                    ForEach(AudioInputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }

                Picker("Target language", selection: Binding(
                    get: { controller.settings.liveTranslationTargetLanguage },
                    set: { controller.settings.liveTranslationTargetLanguage = $0; controller.saveSettings() }
                )) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Stepper(
                    "Update interval: \(controller.settings.liveTranslationIntervalMs) ms",
                    value: Binding(
                        get: { controller.settings.liveTranslationIntervalMs },
                        set: { controller.settings.liveTranslationIntervalMs = $0; controller.saveSettings() }
                    ),
                    in: 600...3000,
                    step: 100
                )

                Text("Global hotkey still controls push-to-talk dictation. Realtime translation is started from the menu bar button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AccessibilityPermissionRow(controller: controller)

            Button("Request Documents Access") {
                controller.openDocumentsPrivacySettings()
            }
        }
        .padding(16)
        .onAppear(perform: syncHotkeyRecorder)
    }

    private func syncHotkeyRecorder() {
        let hotkeyName = KeyboardShortcuts.Name(HotkeyShortcutNames.toggleRecording)
        let shortcut = controller.settings.hotkey.keyboardShortcut
        guard KeyboardShortcuts.getShortcut(for: hotkeyName) != shortcut else { return }
        KeyboardShortcuts.setShortcut(shortcut, for: hotkeyName)
    }
}

// MARK: - Accessibility Permission Row

private struct AccessibilityPermissionRow: View {
    @ObservedObject var controller: AppController
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Button("Request Accessibility") {
                controller.refreshPermissions(promptForAccessibility: true)
            }
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("После обновления или переустановки", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("macOS не переносит разрешение «Универсальный доступ» автоматически при обновлении или переустановке приложения.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Как исправить:")
                        .fontWeight(.medium)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Откройте Системные настройки → Конфиденциальность → Универсальный доступ")
                        Text("2. Найдите QwenWhisper и удалите его (–)")
                        Text("3. Нажмите «Request Accessibility» снова — разрешение будет запрошено заново")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(width: 340)
            }
        }
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

    @State private var draftName: String = ""
    @State private var draftPrompt: String = ""
    @State private var exampleText: String = RewritePromptBuilder.defaultExampleText
    @State private var resultText: String = ""
    @State private var isRunning = false
    @State private var errorText: String? = nil
    @State private var saveTask: Task<Void, Never>?
    @State private var runTask: Task<Void, Never>?
    @State private var previewRequestID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presetPickerSection
            presetNameSection
            promptEditorSection
            Divider()
            previewSection
        }
        .padding(16)
        .onAppear {
            controller.settings.normalizePromptPresets()
            syncDraftFromPreset()
        }
        .onDisappear {
            cancelPendingTasks(flushChanges: true)
        }
    }

    // MARK: - Preset Picker

    private var presetPickerSection: some View {
        HStack {
            Text("Пресет")
                .font(.headline)

            Picker("Пресет", selection: Binding(
                get: { controller.settings.selectedPresetID },
                set: { newID in
                    flushSave()
                    controller.settings.selectedPresetID = newID
                    controller.saveSettings()
                    syncDraftFromPreset()
                    scheduleRun()
                }
            )) {
                ForEach(controller.settings.promptPresets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button(action: addPreset) {
                Image(systemName: "plus")
            }
            .help("Добавить пресет")

            Button(action: deleteCurrentPreset) {
                Image(systemName: "minus")
            }
            .help("Удалить пресет")
            .disabled(controller.settings.promptPresets.count <= 1)

            Spacer()

            Button("Reset All") {
                resetAllPresets()
            }
        }
    }

    private var presetNameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Имя пресета")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Название пресета", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draftName) { _, _ in
                    scheduleSave()
                }

            Text("Изменения сохраняются автоматически. Предпросмотр запускается с задержкой после правок.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Prompt Editor

    private var promptEditorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Системный промпт")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $draftPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .onChange(of: draftPrompt) { _, _ in
                    scheduleSave()
                    scheduleRun()
                }

            Text("\(draftPrompt.count) символов")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Предпросмотр")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                // Example input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Пример")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $exampleText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: .infinity)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .onChange(of: exampleText) { _, _ in
                            scheduleRun()
                        }
                }

                // Result output
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Результат")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !resultText.isEmpty && !isRunning {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(resultText, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Скопировать результат")
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if isRunning {
                            VStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Text("Обработка…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                        } else if let error = errorText {
                            ScrollView {
                                Text(error)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(4)
                            }
                            .frame(minHeight: 60, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                Text(resultText.isEmpty ? "Нажмите «Запустить»" : resultText)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(resultText.isEmpty ? .tertiary : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(4)
                            }
                            .frame(minHeight: 60, maxHeight: .infinity)
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
            }

            HStack {
                Spacer()
                Button("Запустить") {
                    runTest()
                }
                .disabled(isRunning || draftPrompt.isEmpty || exampleText.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func addPreset() {
        flushSave()

        let baseName = draftName.isEmpty ? "Пресет" : draftName
        let newPreset = PromptPreset(
            id: UUID().uuidString,
            name: "Копия \(baseName)",
            prompt: draftPrompt
        )
        controller.settings.promptPresets.append(newPreset)
        controller.settings.selectedPresetID = newPreset.id
        controller.saveSettings()
        syncDraftFromPreset()
        scheduleRun()
    }

    private func deleteCurrentPreset() {
        guard controller.settings.promptPresets.count > 1 else { return }
        flushSave()
        controller.settings.promptPresets.removeAll(where: { $0.id == controller.settings.selectedPresetID })
        controller.settings.normalizePromptPresets()
        controller.saveSettings()
        syncDraftFromPreset()
        scheduleRun()
    }

    private func resetAllPresets() {
        cancelPendingTasks(flushChanges: false)
        controller.resetPromptPresets()
        syncDraftFromPreset()
        clearPreviewState()
        scheduleRun()
    }

    private func syncDraftFromPreset() {
        if let preset = controller.settings.promptPresets.first(where: { $0.id == controller.settings.selectedPresetID }) {
            draftName = preset.name
            draftPrompt = preset.prompt
        } else {
            draftName = ""
            draftPrompt = ""
        }
    }

    // MARK: - Save & Run

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        if let idx = controller.settings.promptPresets.firstIndex(where: { $0.id == controller.settings.selectedPresetID }) {
            controller.settings.promptPresets[idx].name = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Без названия"
                : draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            controller.settings.promptPresets[idx].prompt = draftPrompt
        }
        controller.saveSettings()
    }

    private func scheduleRun() {
        let requestID = nextPreviewRequestID()
        runTask?.cancel()

        guard canRunPreview else {
            clearPreviewState()
            return
        }

        runTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, previewRequestID == requestID else { return }
            startPreviewRun(requestID: requestID)
        }
    }

    private func runTest() {
        let requestID = nextPreviewRequestID()
        runTask?.cancel()
        startPreviewRun(requestID: requestID)
    }

    private func startPreviewRun(requestID: Int) {
        let prompt = draftPrompt
        let input = exampleText
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearPreviewState()
            return
        }

        isRunning = true
        errorText = nil
        resultText = ""

        runTask = Task { @MainActor in
            defer {
                if previewRequestID == requestID {
                    isRunning = false
                }
            }

            do {
                let result = try await controller.testRewrite(inputText: input, systemPrompt: prompt)
                guard !Task.isCancelled, previewRequestID == requestID else { return }
                resultText = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, previewRequestID == requestID else { return }
                errorText = error.localizedDescription
            }
        }
    }

    private var canRunPreview: Bool {
        !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearPreviewState() {
        isRunning = false
        errorText = nil
        resultText = ""
    }

    private func nextPreviewRequestID() -> Int {
        previewRequestID += 1
        return previewRequestID
    }

    private func cancelPendingTasks(flushChanges: Bool) {
        runTask?.cancel()
        runTask = nil
        previewRequestID += 1
        isRunning = false

        if flushChanges {
            flushSave()
        } else {
            saveTask?.cancel()
            saveTask = nil
        }
    }
}
