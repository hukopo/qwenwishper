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
    }

    @Published var settings: AppSettings
    @Published var status: PipelineStatus = .idle
    @Published var lastSnapshot: DictationSnapshot?
    @Published var modelAvailability = ModelAvailability()
    @Published var diagnostics: [DiagnosticsEntry] = []
    @Published var microphoneAuthorized = false
    @Published var accessibilityAuthorized = false
    @Published var latestWhisperText = ""
    @Published var latestQwenText = ""
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

    private var isProcessing = false
    private var isRecording = false
    private var hasStarted = false

    var isRecordingActive: Bool { status == .recording }
    var canToggleRecording: Bool { !isProcessing || isRecording }
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
            modelRuntime: modelManager
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

        wireServices()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)
        installHotkey()
        syncLaunchAtLogin()
        populateDefaultPromptIfNeeded()
        promptForLaunchAtLoginIfNeeded()
        refreshStorageSnapshot()
        Task {
            microphoneAuthorized = await permissionManager.ensureMicrophoneAccess()
            record("Microphone access: \(microphoneAuthorized).", level: .info)
        }
        promptForAccessibilityIfNeeded()
        preloadWhisperInBackground()
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            installHotkey()
            syncLaunchAtLogin()
        } catch {
            record(error.localizedDescription, level: .error)
        }
    }

    func refreshPermissions(promptForAccessibility: Bool) {
        Task {
            status = .checkingPermissions
            microphoneAuthorized = await permissionManager.ensureMicrophoneAccess()
            accessibilityAuthorized = permissionManager.isAccessibilityTrusted(prompt: promptForAccessibility)
            status = .idle
            record("Permissions refreshed.", level: .info)
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

    func resetQwenPrompt() {
        settings.qwenSystemPrompt = RewritePromptBuilder.defaultSystemPrompt
        saveSettings()
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
        guard settings.qwenSystemPrompt.isEmpty else { return }
        settings.qwenSystemPrompt = RewritePromptBuilder.defaultSystemPrompt
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

    private func beginRecording() async throws {
        guard !isProcessing else {
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

        try audioCaptureService.startRecording(maxDuration: .seconds(settings.maxRecordingSeconds)) { [weak self] in
            Task { @MainActor in
                self?.hotkeyReleased()
            }
        }

        record("Recording started.", level: .info)
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

        updateModelAvailability(.qwen, to: .processing)
        status = .rewriting
        record("Starting rewrite. sourceLength=\(transcription.text.count).", level: .info)
        let finalText: String
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
