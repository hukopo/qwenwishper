import Foundation

struct LiveTranslationConfiguration: Sendable, Equatable {
    var source: AudioInputSource
    var targetLanguage: TranslationTargetLanguage
    var whisperModelID: String
    var qwenModelID: String
    var updateInterval: Duration
}

struct LiveTranslationUpdate: Sendable, Equatable {
    var transcriptText: String
    var translatedText: String
    var isFinal: Bool
}

protocol SpeechRecognizer: Sendable {
    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload
}

protocol TextRewriter: Sendable {
    func rewrite(inputText: String, locale: Locale, mode: RewriteMode) async throws -> RewriteResultPayload
    /// Rewrite using an explicit system prompt (for testing presets in settings).
    func rewriteWithPrompt(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload
}

protocol TextInjector: Sendable {
    func insert(text: String) throws -> InsertResult
}

protocol AudioCapturing: AnyObject {
    var onAudioLevel: ((Float) -> Void)? { get set }
    func startRecording(maxDuration: Duration, onMaxDurationReached: @escaping @Sendable () -> Void) throws
    func stopRecording() throws -> AudioCaptureService.Recording
    func cancelRecording()
}

protocol PermissionManaging: AnyObject, Sendable {
    func ensureMicrophoneAccess() async -> Bool
    func isScreenCaptureAuthorized() -> Bool
    func requestScreenCaptureAccess() async -> Bool
    func isAccessibilityTrusted(prompt: Bool) -> Bool
}

protocol HotkeyMonitoring: AnyObject {
    var onPress: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    func register(_ descriptor: HotkeyDescriptor) throws
    func unregister()
}

protocol LaunchAtLoginManaging: AnyObject {
    func setEnabled(_ enabled: Bool) throws
}

protocol ModelRuntimeManaging: Sendable {
    func resetAll() async throws
    func cachedAvailability(settings: AppSettings) async -> ModelAvailability
    /// Eagerly loads the Whisper model into memory if it is already downloaded.
    /// No-op if the model is not cached. Safe to call concurrently.
    func preloadWhisperIfCached(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async
    /// Eagerly loads the Qwen model into memory if it is already downloaded and Metal shaders are present.
    /// No-op otherwise. Safe to call concurrently.
    func preloadQwenIfCached(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async
    /// Clears any corrupted/partial Whisper files from disk and re-downloads + loads the model.
    func retryWhisper(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async
    /// Clears any corrupted Qwen state and re-downloads + loads the model.
    func retryQwen(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async
}

protocol LiveTranslating: Sendable {
    func start(
        configuration: LiveTranslationConfiguration,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onUpdate: @escaping @Sendable (LiveTranslationUpdate) -> Void
    ) async throws

    func stop() async
}
