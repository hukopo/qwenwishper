import Foundation
import Testing
@testable import QwenWhisperApp

@Test
func sanitizeRemovesCodeFencesAndWhitespace() {
    let output = """
    ```text
    Привет,   мир.
    ```
    """

    #expect(RewritePromptBuilder.sanitizeModelOutput(output) == "Привет, мир.")
}

@Test
func russianSystemPromptPreservesMeaningConstraint() {
    let prompt = RewritePromptBuilder.systemPrompt(mode: .aggressive, locale: Locale(identifier: "ru_RU"))
    #expect(prompt.contains("Сохраняй исходный смысл"))
    #expect(prompt.contains("Не добавляй новые факты"))
}

@Test
func fallbackSystemPromptPreservesMeaningConstraint() {
    let prompt = RewritePromptBuilder.systemPrompt(mode: .aggressive, locale: Locale(identifier: "en_US"))
    #expect(prompt.contains("Preserve meaning"))
    #expect(prompt.contains("Do not summarize"))
}

@Test
func settingsStoreReturnsDefaultsWhenEmpty() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = SettingsStore(defaults: defaults)

    #expect(store.load() == .defaults)
}

@Test
func settingsStoreRoundTripsSettings() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = SettingsStore(defaults: defaults)

    var settings = AppSettings.defaults
    settings.pasteDelayMs = 240
    settings.hotkey = HotkeyDescriptor.Preset.controlOptionSpace.descriptor

    try store.save(settings)

    #expect(store.load() == settings)
}

@Test
func readableNameMatchesKeyboardShortcutDescription() {
    let descriptor = HotkeyDescriptor.Preset.commandShiftSpace.descriptor
    #expect(descriptor.readableName == descriptor.keyboardShortcut.description)
}

@Test
func settingsStoreMigratesLegacyPromptIntoEditorPreset() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = SettingsStore(defaults: defaults)

    let legacyPrompt = "Сделай текст вежливее, но не меняй смысл."
    let defaultsData = try JSONEncoder().encode(AppSettings.defaults)
    var payload = try #require(JSONSerialization.jsonObject(with: defaultsData) as? [String: Any])
    payload.removeValue(forKey: "promptPresets")
    payload.removeValue(forKey: "selectedPresetID")
    payload["qwenSystemPrompt"] = legacyPrompt
    defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "app_settings")

    let loaded = store.load()
    let editorPreset = loaded.promptPresets.first(where: { $0.id == RewritePromptBuilder.defaultPresetID })

    #expect(editorPreset?.prompt == legacyPrompt)
    #expect(loaded.selectedPresetID == RewritePromptBuilder.defaultPresetID)
}

@Test
func settingsStoreNormalizesMissingSelectedPreset() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = SettingsStore(defaults: defaults)

    let defaultsData = try JSONEncoder().encode(AppSettings.defaults)
    var payload = try #require(JSONSerialization.jsonObject(with: defaultsData) as? [String: Any])
    payload["selectedPresetID"] = "missing-preset"
    defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "app_settings")

    let loaded = store.load()

    #expect(loaded.selectedPresetID == RewritePromptBuilder.defaultPresetID)
    #expect(loaded.qwenSystemPrompt == RewritePromptBuilder.defaultSystemPrompt)
}

@MainActor
@Test
func appControllerCompletesThePipelineWithInjectedServices() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let settingsStore = SettingsStore(defaults: defaults)
    let logger = AppLogger()
    let permissions = MockPermissionManager(microphoneAllowed: true, accessibilityAllowed: true)
    let hotkeys = MockHotkeyMonitor()
    let audio = MockAudioCaptureService(durationSeconds: 1.25)
    let recognizer = MockSpeechRecognizer(resultText: "привет мир")
    let rewriter = MockTextRewriter(resultText: "Привет, мир.")
    let injector = MockTextInjector()
    let models = MockModelRuntime()

    let controller = AppController(
        settings: .defaults,
        dependencies: .init(
            settingsStore: settingsStore,
            logger: logger,
            permissionManager: permissions,
            launchAtLoginService: MockLaunchAtLoginService(),
            hotkeyMonitor: hotkeys,
            audioCaptureService: audio,
            speechRecognizer: recognizer,
            textRewriter: rewriter,
            textInjector: injector,
            modelRuntime: models,
            liveTranslator: MockLiveTranslator()
        )
    )

    await controller.toggleRecording()
    #expect(controller.isRecordingActive)

    await controller.toggleRecording()

    #expect(controller.status == PipelineStatus.idle)
    #expect(controller.lastSnapshot?.sourceText == "привет мир")
    #expect(controller.lastSnapshot?.rewrittenText == "Привет, мир.")
    #expect(controller.lastSnapshot?.insertMethod == .accessibility)
    #expect(audio.startCalls == 1)
    #expect(audio.stopCalls == 1)
    #expect(await recognizer.callCount == 1)
    #expect(await rewriter.callCount == 1)
    #expect(injector.insertedTexts == ["Привет, мир."])
}

@MainActor
@Test
func appControllerStopsBeforeTranscriptionForTooShortRecordings() async throws {
    let defaults = UserDefaults(suiteName: #function + "-short")!
    defaults.removePersistentDomain(forName: #function + "-short")
    let settingsStore = SettingsStore(defaults: defaults)
    let logger = AppLogger()
    let audio = MockAudioCaptureService(durationSeconds: 0.01)
    let recognizer = MockSpeechRecognizer(resultText: "ignored")
    let rewriter = MockTextRewriter(resultText: "ignored")
    let injector = MockTextInjector()

    let controller = AppController(
        settings: .defaults,
        dependencies: .init(
            settingsStore: settingsStore,
            logger: logger,
            permissionManager: MockPermissionManager(microphoneAllowed: true, accessibilityAllowed: true),
            launchAtLoginService: MockLaunchAtLoginService(),
            hotkeyMonitor: MockHotkeyMonitor(),
            audioCaptureService: audio,
            speechRecognizer: recognizer,
            textRewriter: rewriter,
            textInjector: injector,
            modelRuntime: MockModelRuntime(),
            liveTranslator: MockLiveTranslator()
        )
    )

    await controller.toggleRecording()
    await controller.toggleRecording()

    if case .error(let message) = controller.status {
        #expect(message.contains("No speech"))
    } else {
        Issue.record("Expected an error status for an empty recording.")
    }
    #expect(await recognizer.callCount == 0)
    #expect(await rewriter.callCount == 0)
    #expect(injector.insertedTexts.isEmpty)
}

@MainActor
@Test
func appControllerFailsFastWhenMicrophonePermissionIsDenied() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let settingsStore = SettingsStore(defaults: defaults)
    let controller = AppController(
        settings: .defaults,
        dependencies: .init(
            settingsStore: settingsStore,
            logger: AppLogger(),
            permissionManager: MockPermissionManager(microphoneAllowed: false, accessibilityAllowed: true),
            launchAtLoginService: MockLaunchAtLoginService(),
            hotkeyMonitor: MockHotkeyMonitor(),
            audioCaptureService: MockAudioCaptureService(durationSeconds: 1),
            speechRecognizer: MockSpeechRecognizer(resultText: "ignored"),
            textRewriter: MockTextRewriter(resultText: "ignored"),
            textInjector: MockTextInjector(),
            modelRuntime: MockModelRuntime(),
            liveTranslator: MockLiveTranslator()
        )
    )

    await controller.toggleRecording()

    if case .error(let message) = controller.status {
        #expect(message.contains("Microphone access"))
    } else {
        Issue.record("Expected a microphone permission error.")
    }
    #expect(!controller.isRecordingActive)
}

private final class MockPermissionManager: PermissionManaging, @unchecked Sendable {
    let microphoneAllowed: Bool
    let accessibilityAllowed: Bool
    let screenCaptureAllowed: Bool

    init(microphoneAllowed: Bool, accessibilityAllowed: Bool, screenCaptureAllowed: Bool = true) {
        self.microphoneAllowed = microphoneAllowed
        self.accessibilityAllowed = accessibilityAllowed
        self.screenCaptureAllowed = screenCaptureAllowed
    }

    func ensureMicrophoneAccess() async -> Bool { microphoneAllowed }
    func isScreenCaptureAuthorized() -> Bool { screenCaptureAllowed }
    func requestScreenCaptureAccess() async -> Bool { screenCaptureAllowed }
    func isAccessibilityTrusted(prompt: Bool) -> Bool { accessibilityAllowed }
}

private final class MockHotkeyMonitor: HotkeyMonitoring {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private(set) var registeredDescriptor: HotkeyDescriptor?

    func register(_ descriptor: HotkeyDescriptor) throws {
        registeredDescriptor = descriptor
    }

    func unregister() {
        registeredDescriptor = nil
    }
}

private final class MockLaunchAtLoginService: LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

private final class MockAudioCaptureService: AudioCapturing {
    var onAudioLevel: ((Float) -> Void)?
    private let recordingURL: URL
    private let durationSecondsValue: TimeInterval
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    init(durationSeconds: TimeInterval) {
        self.durationSecondsValue = durationSeconds
        self.recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        FileManager.default.createFile(atPath: recordingURL.path, contents: Data("audio".utf8))
    }

    func startRecording(maxDuration: Duration, onMaxDurationReached: @escaping @Sendable () -> Void) throws {
        startCalls += 1
    }

    func stopRecording() throws -> AudioCaptureService.Recording {
        stopCalls += 1
        return .init(url: recordingURL, durationSeconds: durationSecondsValue)
    }

    func cancelRecording() {}
}

private actor MockSpeechRecognizer: SpeechRecognizer {
    let resultText: String
    private(set) var callCount = 0

    init(resultText: String) {
        self.resultText = resultText
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload {
        callCount += 1
        return .init(text: resultText, latency: .milliseconds(120), audioURL: audioURL)
    }
}

private actor MockTextRewriter: TextRewriter {
    let resultText: String
    private(set) var callCount = 0

    init(resultText: String) {
        self.resultText = resultText
    }

    func rewrite(inputText: String, locale: Locale, mode: RewriteMode) async throws -> RewriteResultPayload {
        callCount += 1
        return .init(sourceText: inputText, rewrittenText: resultText, latency: .milliseconds(80))
    }

    func rewriteWithPrompt(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload {
        callCount += 1
        return .init(sourceText: inputText, rewrittenText: resultText, latency: .milliseconds(80))
    }
}

private final class MockTextInjector: TextInjector, @unchecked Sendable {
    private(set) var insertedTexts: [String] = []

    func insert(text: String) throws -> InsertResult {
        insertedTexts.append(text)
        return .init(method: .accessibility)
    }
}

private actor MockModelRuntime: ModelRuntimeManaging {
    func resetAll() async throws {}
    func cachedAvailability(settings: AppSettings) async -> ModelAvailability { .init() }
    func preloadWhisperIfCached(
        settings: AppSettings,
        progress: @escaping @Sendable (ModelAvailability.State) -> Void
    ) async {}

    func preloadQwenIfCached(
        settings: AppSettings,
        progress: @escaping @Sendable (ModelAvailability.State) -> Void
    ) async {}

    func retryWhisper(
        settings: AppSettings,
        progress: @escaping @Sendable (ModelAvailability.State) -> Void
    ) async {}

    func retryQwen(
        settings: AppSettings,
        progress: @escaping @Sendable (ModelAvailability.State) -> Void
    ) async {}
}

private actor MockLiveTranslator: LiveTranslating {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(
        configuration: LiveTranslationConfiguration,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onUpdate: @escaping @Sendable (LiveTranslationUpdate) -> Void
    ) async throws {
        startCallCount += 1
        onAudioLevel(-24)
        onUpdate(.init(
            transcriptText: "hello world",
            translatedText: configuration.targetLanguage.usesWhisperNativeTranslation ? "hello world" : "привет мир",
            isFinal: false
        ))
    }

    func stop() async {
        stopCallCount += 1
    }
}

@MainActor
@Test
func appControllerStartsAndStopsLiveTranslationWithInjectedService() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let settingsStore = SettingsStore(defaults: defaults)
    let permissions = MockPermissionManager(
        microphoneAllowed: true,
        accessibilityAllowed: true,
        screenCaptureAllowed: true
    )
    let liveTranslator = MockLiveTranslator()
    var settings = AppSettings.defaults
    settings.liveTranslationTargetLanguage = .russian

    let controller = AppController(
        settings: settings,
        dependencies: .init(
            settingsStore: settingsStore,
            logger: AppLogger(),
            permissionManager: permissions,
            launchAtLoginService: MockLaunchAtLoginService(),
            hotkeyMonitor: MockHotkeyMonitor(),
            audioCaptureService: MockAudioCaptureService(durationSeconds: 1),
            speechRecognizer: MockSpeechRecognizer(resultText: "ignored"),
            textRewriter: MockTextRewriter(resultText: "ignored"),
            textInjector: MockTextInjector(),
            modelRuntime: MockModelRuntime(),
            liveTranslator: liveTranslator
        )
    )

    await controller.toggleLiveTranslation()

    #expect(controller.isLiveTranslationActive)
    #expect(controller.latestLiveTranscriptText == "hello world")
    #expect(controller.latestLiveTranslationText == "привет мир")
    #expect(await liveTranslator.startCallCount == 1)

    await controller.toggleLiveTranslation()

    #expect(!controller.isLiveTranslationActive)
    #expect(controller.status == PipelineStatus.idle)
    #expect(await liveTranslator.stopCallCount == 1)
}
