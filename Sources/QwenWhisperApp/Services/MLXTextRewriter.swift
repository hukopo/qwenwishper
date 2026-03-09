import Foundation
import MLX
import MLXLLM
import MLXLMCommon

actor MLXTextRewriter: TextRewriter {
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

    func rewrite(inputText: String, locale: Locale, mode: RewriteMode) async throws -> RewriteResultPayload {
        let settings = settingsProvider()
        let modelContainer = try await modelManager.prepareQwen(settings: settings, progress: progress)
        return try await rewriteText(
            modelContainer: modelContainer,
            inputText: inputText,
            locale: locale,
            mode: mode,
            systemPromptOverride: settings.qwenSystemPrompt
        ) { message in
            DiagnosticTrace.write(message)
        }
    }
}
