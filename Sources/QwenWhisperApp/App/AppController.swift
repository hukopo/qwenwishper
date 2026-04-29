import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    struct Dependencies {
        let settingsStore: SettingsStore
        let logger: AppLogger
        let permissionManager: PermissionManaging
        let launchAtLoginService: LaunchAtLoginManaging
        let hotkeyMonitor: HotkeyMonitoring
        let audioCaptureService: AudioCapturing
        let speechRecognizer: SpeechRecognizer
        let textRewriter: TextRewriter
        let textInjector: TextInjector
        let modelRuntime: ModelRuntimeManaging
        let liveTranslator: LiveTranslating
    }

    @Published var settings: AppSettings
    @Published var status: PipelineStatus = .idle
    @Published var audioLevel: Float = -160
    @Published var lastSnapshot: DictationSnapshot?
    @Published var modelAvailability = ModelAvailability()
    @Published var diagnostics: [DiagnosticsEntry] = []
    @Published var microphoneAuthorized = false
    @Published var screenCaptureAuthorized = false
    @Published var accessibilityAuthorized = false
    @Published var latestWhisperText = ""
    @Published var latestQwenText = ""
    @Published var latestLiveTranscriptText = ""
    @Published var latestLiveTranslationText = ""
    @Published var liveTranslationSnapshot: LiveTranslationSnapshot?
    @Published var storageSnapshot = StorageSnapshot(
        appURL: Bundle.main.bundleURL,
        appSizeBytes: 0,
        modelsURL: StorageService.makeModelsURL(),
        modelsSizeBytes: 0,
        recordingsURL: StorageService.makeRecordingsURL(),
        recordingsSizeBytes: 0
    )

    private let settingsStore: SettingsStore
    private let logger: AppLogger
    private let permissionManager: PermissionManaging
    private let launchAtLoginService: LaunchAtLoginManaging
    private let hotkeyMonitor: HotkeyMonitoring
    private let audioCaptureService: AudioCapturing
    private let speechRecognizer: SpeechRecognizer
    private let textRewriter: TextRewriter
    private let textInjector: TextInjector
    private let modelRuntime: ModelRuntimeManaging
    private let liveTranslator: LiveTranslating

    private var isProcessing = false
    private var isRecording = false
    private var isRealtimeActive = false
    private var hasStarted = false
    private let floatingPanel = FloatingStatusPanel()

    var isRecordingActive: Bool { status == .recording }
    var isLiveTranslationActive: Bool { isRealtimeActive }
    var canToggleRecording: Bool { (!isProcessing && !isRealtimeActive) || isRecording }
    var canToggleLiveTranslation: Bool { (!isProcessing && !isRecording) || isRealtimeActive }
    var diagnosticsText: String {
        diagnostics
            .map {
                "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.level.rawValue.uppercased()): \($0.message)"
            }
            .joined(separator: "\n")
    }

    convenience init() {
        let settingsStore = SettingsStore()
        let settings = settingsStore.load()
        let logger = AppLogger()
        let permissionManager = PermissionManager()
        let modelManager = ModelManager()

        // WeakBoxes let us bind the progress closures to AppController after self.init().
        let whisperBox = WeakBox<AppController>()
        let qwenBox = WeakBox<AppController>()

        let speechRecognizer = WhisperSpeechRecognizer(
            modelManager: modelManager,
            settingsProvider: { [settingsStore] in settingsStore.load() },
            progress: { @Sendable [whisperBox] state in
                Task { @MainActor in whisperBox.value?.updateModelAvailability(.whisper, to: state) }
            }
        )
        let textRewriter = MLXTextRewriter(
            modelManager: modelManager,
            settingsProvider: { [settingsStore] in settingsStore.load() },
            progress: { @Sendable [qwenBox] state in
                Task { @MainActor in qwenBox.value?.updateModelAvailability(.qwen, to: state) }
            }
        )
        let dependencies = Dependencies(
            settingsStore: settingsStore,
            logger: logger,
            permissionManager: permissionManager,
            launchAtLoginService: LaunchAtLoginService(),
            hotkeyMonitor: HotkeyMonitor(),
            audioCaptureService: AudioCaptureService(),
            speechRecognizer: speechRecognizer,
            textRewriter: textRewriter,
            textInjector: PasteService(),
            modelRuntime: modelManager,
            liveTranslator: RealtimeTranslationService(modelManager: modelManager)
        )

        self.init(settings: settings, dependencies: dependencies)
        whisperBox.value = self
        qwenBox.value = self
    }

    init(settings: AppSettings, dependencies: Dependencies) {
        self.settings = settings
        self.settingsStore = dependencies.settingsStore
        self.logger = dependencies.logger
        self.permissionManager = dependencies.permissionManager
        self.launchAtLoginService = dependencies.launchAtLoginService
        self.hotkeyMonitor = dependencies.hotkeyMonitor
        self.audioCaptureService = dependencies.audioCaptureService
        self.speechRecognizer = dependencies.speechRecognizer
        self.textRewriter = dependencies.textRewriter
        self.textInjector = dependencies.textInjector
        self.modelRuntime = dependencies.modelRuntime
        self.liveTranslator = dependencies.liveTranslator

        wireServices()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)
        floatingPanel.setup(controller: self)
        installHotkey()
        syncLaunchAtLogin()
        populateDefaultPromptIfNeeded()
        promptForLaunchAtLoginIfNeeded()
        refreshStorageSnapshot()
        Task {
            microphoneAuthorized = await permissionManager.ensureMicrophoneAccess()
            screenCaptureAuthorized = permissionManager.isScreenCaptureAuthorized()
            record("Microphone access: \(microphoneAuthorized).", level: .info)
            record("Screen capture access: \(screenCaptureAuthorized).", level: .info)
        }
        promptForAccessibilityIfNeeded()
        preloadWhisperInBackground()
        if settings.qwenEnabled {
            preloadQwenInBackground()
        } else {
            modelAvailability.qwen = .disabled
        }
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            installHotkey()
            syncLaunchAtLogin()
            syncQwenEnabledState()
        } catch {
            record(error.localizedDescription, level: .error)
        }
    }

    /// Reflects the current `settings.qwenEnabled` in `modelAvailability` immediately,
    /// and kicks off a background preload when Qwen is turned on for the first time.
    private func syncQwenEnabledState() {
        if settings.qwenEnabled {
            // If it was just enabled and not yet loaded, kick off preload.
            if modelAvailability.qwen == .disabled {
                modelAvailability.qwen = .idle
                preloadQwenInBackground()
            }
        } else {
            modelAvailability.qwen = .disabled
        }
    }

    func refreshPermissions(promptForAccessibility: Bool) {
        Task {
            status = .checkingPermissions
            microphoneAuthorized = await permissionManager.ensureMicrophoneAccess()
            screenCaptureAuthorized = promptForAccessibility ? await permissionManager.requestScreenCaptureAccess() : permissionManager.isScreenCaptureAuthorized()
            accessibilityAuthorized = permissionManager.isAccessibilityTrusted(prompt: promptForAccessibility)
            status = .idle
            record("Permissions refreshed.", level: .info)
        }
    }

    func dismissError() {
        if case .error = status { status = .idle }
    }

    func openDocumentsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearModels() {
        Task {
            do {
                try await modelRuntime.resetAll()
                modelAvailability = ModelAvailability()
                record("Model caches removed.", level: .warning)
                refreshStorageSnapshot()
            } catch {
                record(error.localizedDescription, level: .error)
            }
        }
    }

    func clearRecordings() {
        Task {
            do {
                try await StorageService.clearRecordings()
                record("Recordings cleared.", level: .warning)
                refreshStorageSnapshot()
            } catch {
                record(error.localizedDescription, level: .error)
            }
        }
    }

    func openModelsFolder() {
        StorageService.openModelsFolder()
    }

    func openRecordingsFolder() {
        StorageService.openRecordingsFolder()
    }

    func revealAppInFinder() {
        StorageService.revealAppInFinder()
    }

    func resetPromptPresets() {
        settings.promptPresets = RewritePromptBuilder.defaultPresets
        settings.selectedPresetID = RewritePromptBuilder.defaultPresetID
        saveSettings()
    }

    /// Run a test rewrite with an explicit system prompt (used by the Prompt settings preview).
    func testRewrite(inputText: String, systemPrompt: String) async throws -> String {
        let result = try await textRewriter.rewriteWithPrompt(inputText: inputText, systemPrompt: systemPrompt)
        return result.rewrittenText
    }

    func retryModel(_ kind: ModelKind) {
        let currentSettings = settings
        Task {
            switch kind {
            case .whisper:
                record("Retrying Whisper model download.", level: .info)
                updateModelAvailability(.whisper, to: .downloading(0))
                await modelRuntime.retryWhisper(
                    settings: currentSettings,
                    progress: { @Sendable [weak self] state in
                        Task { @MainActor in self?.updateModelAvailability(.whisper, to: state) }
                    }
                )
            case .qwen:
                record("Retrying Qwen model download.", level: .info)
                updateModelAvailability(.qwen, to: .downloading(0))
                await modelRuntime.retryQwen(
                    settings: currentSettings,
                    progress: { @Sendable [weak self] state in
                        Task { @MainActor in self?.updateModelAvailability(.qwen, to: state) }
                    }
                )
            }
            refreshStorageSnapshot()
        }
    }

    private func populateDefaultPromptIfNeeded() {
        let oldSettings = settings
        settings.normalizePromptPresets()

        guard settings != oldSettings else { return }
        saveSettings()
    }

    func hotkeyPressed() {
        Task {
            await toggleRecording()
        }
    }

    func hotkeyReleased() {
        // Toggle mode: release events are ignored on purpose.
    }

    func toggleRecordingFromUI() {
        hotkeyPressed()
    }

    func toggleLiveTranslationFromUI() {
        Task {
            await toggleLiveTranslation()
        }
    }

    func toggleRecording() async {
        do {
            if isRecording {
                record("Toggle requested: stop recording.", level: .info)
                try await finishRecordingAndProcess()
            } else {
                guard !isProcessing else { return }
                record("Toggle requested: start recording.", level: .info)
                try await beginRecording()
            }
        } catch {
            handle(error)
        }
    }

    func toggleLiveTranslation() async {
        do {
            if isRealtimeActive {
                record("Toggle requested: stop live translation.", level: .info)
                await stopLiveTranslation()
            } else {
                guard !isProcessing, !isRecording else {
                    throw AppFailure.alreadyBusy
                }
                record("Toggle requested: start live translation.", level: .info)
                try await startLiveTranslation()
            }
        } catch {
            handle(error)
        }
    }

    private func beginRecording() async throws {
        guard !isProcessing, !isRealtimeActive else {
            throw AppFailure.alreadyBusy
        }
        latestWhisperText = ""
        latestQwenText = ""
        let microphoneGranted: Bool
        if microphoneAuthorized {
            microphoneGranted = true
        } else {
            microphoneGranted = await permissionManager.ensureMicrophoneAccess()
        }
        record("Microphone access state: \(microphoneGranted).", level: .info)
        guard microphoneGranted else {
            throw AppFailure.microphoneDenied
        }
        let accessibilityGranted = accessibilityAuthorized || permissionManager.isAccessibilityTrusted(prompt: true)
        record("Accessibility access state: \(accessibilityGranted).", level: .info)
        guard accessibilityGranted else {
            throw AppFailure.accessibilityDenied
        }

        microphoneAuthorized = true
        accessibilityAuthorized = true
        status = .recording
        isRecording = true

        audioCaptureService.onAudioLevel = { [weak self] level in
            self?.audioLevel = level
        }
        try audioCaptureService.startRecording(maxDuration: .seconds(settings.maxRecordingSeconds)) { [weak self] in
            Task { @MainActor in
                self?.hotkeyReleased()
            }
        }

        record("Recording started.", level: .info)
    }

    private func startLiveTranslation() async throws {
        guard !isRealtimeActive, !isProcessing, !isRecording else {
            throw AppFailure.alreadyBusy
        }

        latestLiveTranscriptText = ""
        latestLiveTranslationText = ""
        liveTranslationSnapshot = nil

        switch settings.liveAudioSource {
        case .microphone:
            let microphoneGranted = microphoneAuthorized ? true : await permissionManager.ensureMicrophoneAccess()
            record("Realtime microphone access state: \(microphoneGranted).", level: .info)
            guard microphoneGranted else {
                throw AppFailure.microphoneDenied
            }
            microphoneAuthorized = true
        case .systemAudio:
            let screenGranted = screenCaptureAuthorized ? true : await permissionManager.requestScreenCaptureAccess()
            record("Screen capture access state: \(screenGranted).", level: .info)
            guard screenGranted else {
                throw AppFailure.screenCaptureDenied
            }
            screenCaptureAuthorized = true
        }

        isRealtimeActive = true
        status = .liveCapturing
        audioLevel = -160

        let configuration = LiveTranslationConfiguration(
            source: settings.liveAudioSource,
            targetLanguage: settings.liveTranslationTargetLanguage,
            whisperModelID: settings.whisperModelID,
            qwenModelID: settings.qwenModelID,
            updateInterval: .milliseconds(settings.liveTranslationIntervalMs)
        )

        do {
            try await liveTranslator.start(
                configuration: configuration,
                onAudioLevel: { [weak self] level in
                    Task { @MainActor in
                        self?.audioLevel = level
                    }
                },
                onUpdate: { [weak self] update in
                    Task { @MainActor in
                        guard let self else { return }
                        self.latestLiveTranscriptText = update.transcriptText
                        self.latestLiveTranslationText = update.translatedText
                        self.liveTranslationSnapshot = .init(
                            transcriptText: update.transcriptText,
                            translatedText: update.translatedText,
                            finishedAt: Date()
                        )

                        if self.settings.liveTranslationTargetLanguage.usesWhisperNativeTranslation {
                            self.status = .liveTranscribing
                        } else if update.translatedText != update.transcriptText {
                            self.status = .liveTranslating
                        } else {
                            self.status = .liveTranscribing
                        }
                    }
                }
            )
        } catch {
            isRealtimeActive = false
            status = .idle
            throw error
        }

        record(
            "Live translation started. source=\(settings.liveAudioSource.rawValue) target=\(settings.liveTranslationTargetLanguage.rawValue).",
            level: .info
        )
    }

    private func stopLiveTranslation() async {
        guard isRealtimeActive else { return }
        isRealtimeActive = false
        await liveTranslator.stop()
        audioLevel = -160
        if case .error = status {
            // Preserve current error state.
        } else {
            status = .idle
        }
        record("Live translation stopped.", level: .info)
    }

    private func finishRecordingAndProcess() async throws {
        guard isRecording else {
            throw AppFailure.recordingNotActive
        }

        isRecording = false
        isProcessing = true

        defer {
            isProcessing = false
            if case .error = status {
                // Preserve the current error status until the next successful run.
            } else {
                status = .idle
            }
        }

        audioCaptureService.onAudioLevel = nil
        audioLevel = -160
        let recording = try audioCaptureService.stopRecording()
        record(
            "Recording finished: \(recording.url.lastPathComponent) (\(String(format: "%.2f", recording.durationSeconds))s).",
            level: .info
        )
        guard recording.durationSeconds > 0.05 else {
            record("Rejecting recording as empty due to duration threshold.", level: .warning)
            throw AppFailure.emptySpeech
        }

        updateModelAvailability(.whisper, to: .processing)
        status = .transcribing
        record("Starting transcription for \(recording.url.lastPathComponent).", level: .info)
        let transcription = try await speechRecognizer.transcribe(audioURL: recording.url)
        updateModelAvailability(.whisper, to: .ready)
        latestWhisperText = transcription.text
        record(
            "Transcribed \(String(format: "%.2f", transcription.latency.secondsValue))s audio. textLength=\(transcription.text.count).",
            level: .info
        )
        record("Whisper text: \(transcription.text)", level: .info)

        let finalText: String
        if settings.qwenEnabled {
            updateModelAvailability(.qwen, to: .processing)
            status = .rewriting
            record("Starting rewrite. sourceLength=\(transcription.text.count).", level: .info)
            do {
                let rewrite = try await textRewriter.rewrite(
                    inputText: transcription.text,
                    locale: Locale(identifier: "ru_RU"),
                    mode: .aggressive
                )
                updateModelAvailability(.qwen, to: .ready)
                record(
                    "Rewriter finished in \(String(format: "%.2f", rewrite.latency.secondsValue))s. rewrittenLength=\(rewrite.rewrittenText.count).",
                    level: .info
                )
                finalText = rewrite.rewrittenText
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                updateModelAvailability(.qwen, to: .failed(message))
                record("Rewrite fallback: \(message)", level: .warning)
                finalText = transcription.text
            }
        } else {
            // Qwen is disabled — paste Whisper text directly without rewriting.
            record("Qwen disabled, skipping rewrite.", level: .info)
            finalText = transcription.text
        }
        latestQwenText = finalText

        status = .pasting
        try await Task.sleep(for: .milliseconds(settings.pasteDelayMs))
        let insertResult = try textInjector.insert(text: finalText)
        lastSnapshot = DictationSnapshot(
            sourceText: transcription.text,
            rewrittenText: finalText,
            insertMethod: insertResult.method,
            finishedAt: Date()
        )
        record("Inserted text using \(insertResult.method.rawValue).", level: .info)
        refreshCachedModelAvailability()
        refreshStorageSnapshot()
    }

    private func installHotkey() {
        do {
            hotkeyMonitor.onPress = { [weak self] in
                Task { @MainActor in
                    self?.hotkeyPressed()
                }
            }
            hotkeyMonitor.onRelease = { [weak self] in
                Task { @MainActor in
                    self?.hotkeyReleased()
                }
            }
            try hotkeyMonitor.register(settings.hotkey)
            record("Registered hotkey \(settings.hotkey.readableName).", level: .info)
        } catch {
            handle(error)
        }
    }

    private func syncLaunchAtLogin() {
        do {
            try launchAtLoginService.setEnabled(settings.launchAtLogin)
        } catch {
            record("Launch at login update failed: \(error.localizedDescription)", level: .warning)
        }
    }

    private func promptForLaunchAtLoginIfNeeded() {
        guard settings.didPromptLaunchAtLogin == false else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Launch QwenWhisper at login?"
            alert.informativeText = "QwenWhisper works best as a menu bar utility that starts with macOS."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Not now")
            alert.alertStyle = .informational

            let response = alert.runModal()
            settings.didPromptLaunchAtLogin = true

            if response == .alertFirstButtonReturn {
                settings.launchAtLogin = true
                record("User enabled launch at login from first-run prompt.", level: .info)
            } else {
                record("User skipped launch at login from first-run prompt.", level: .info)
            }

            saveSettings()
        }
    }

    private func promptForAccessibilityIfNeeded() {
        Task { @MainActor in
            // Give the run loop a moment to finish launching before prompting.
            try? await Task.sleep(for: .milliseconds(600))
            // prompt:true shows the standard macOS system dialog if not yet trusted,
            // and returns immediately (true) if already trusted — no extra alert needed.
            accessibilityAuthorized = permissionManager.isAccessibilityTrusted(prompt: true)
            record("Accessibility check at launch: granted=\(accessibilityAuthorized)", level: .info)
        }
    }

    private func wireServices() {
        diagnostics = logger.entries
    }

    private func refreshCachedModelAvailability() {
        Task {
            let availability = await modelRuntime.cachedAvailability(settings: settings)
            modelAvailability = availability
        }
    }

    func refreshStorageSnapshot() {
        Task {
            storageSnapshot = await StorageService.snapshot()
        }
    }

    func updateModelAvailability(_ kind: ModelKind, to state: ModelAvailability.State) {
        switch kind {
        case .whisper:
            modelAvailability.whisper = state
        case .qwen:
            modelAvailability.qwen = state
        }
    }

    private func preloadWhisperInBackground() {
        let currentSettings = settings
        Task {
            await modelRuntime.preloadWhisperIfCached(
                settings: currentSettings,
                progress: { @Sendable [weak self] state in
                    Task { @MainActor in self?.updateModelAvailability(.whisper, to: state) }
                }
            )
            // Sync cached state in case preload changed availability.
            let availability = await modelRuntime.cachedAvailability(settings: currentSettings)
            modelAvailability = availability
        }
    }

    private func preloadQwenInBackground() {
        let currentSettings = settings
        Task {
            await modelRuntime.preloadQwenIfCached(
                settings: currentSettings,
                progress: { @Sendable [weak self] state in
                    Task { @MainActor in self?.updateModelAvailability(.qwen, to: state) }
                }
            )
            // Sync cached state after preload completes.
            let availability = await modelRuntime.cachedAvailability(settings: currentSettings)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only update Qwen slot to avoid overwriting Whisper preload progress.
                self.modelAvailability.qwen = availability.qwen
            }
        }
    }

    private func record(_ message: String, level: DiagnosticsEntry.Level) {
        switch level {
        case .info:
            logger.info(message)
        case .warning:
            logger.warning(message)
        case .error:
            logger.error(message)
        }
        diagnostics = logger.entries
    }

    private func handle(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        status = .error(message)
        refreshCachedModelAvailability()
        DiagnosticTrace.write("AppController.handle errorType=\(String(describing: type(of: error))) message=\(message)")
        record(message, level: .error)

        // When microphone is denied macOS won't show the dialog again —
        // open System Settings so the user can toggle it there.
        if let failure = error as? AppFailure, failure == .microphoneDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    enum ModelKind {
        case whisper
        case qwen
    }
}

/// Thread-safe weak reference holder used to break retain cycles in @Sendable closures
/// that need to call back to AppController after it is initialised.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init() {}
}
