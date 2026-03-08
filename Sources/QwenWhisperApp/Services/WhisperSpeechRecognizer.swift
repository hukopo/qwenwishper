import Foundation

actor WhisperSpeechRecognizer: SpeechRecognizer {
    private let modelManager: ModelManager
    private let settingsProvider: @Sendable () -> AppSettings
    private let progress: @Sendable (ModelAvailability.State) -> Void

    init(
        modelManager: ModelManager,
        settingsProvider: @escaping @Sendable () -> AppSettings,
        progress: @escaping @Sendable (ModelAvailability.State) -> Void
    ) {
        self.modelManager = modelManager
        self.settingsProvider = settingsProvider
        self.progress = progress
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload {
        let settings = settingsProvider()
        return try await modelManager.transcribe(audioURL: audioURL, settings: settings, progress: progress)
    }
}
