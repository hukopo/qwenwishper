import Foundation
import Hub
import MLX
import MLXLMCommon

func loadQwenContainerOnCPU(
    rootURL: URL,
    modelID: String,
    downloadProgress: @escaping @Sendable (Double) -> Void = { _ in },
    /// Called after all model files are present on disk but before weights are loaded into memory.
    /// Use this to transition the UI from "downloading…" to "loading…".
    onDownloadComplete: @escaping @Sendable () -> Void = {},
    progress: @escaping @Sendable (String) -> Void
) async throws -> (modelDirectory: URL, container: ModelContainer) {
    try await Device.withDefaultDevice(.cpu) {
        progress("Qwen CPU helper entered.")
        Memory.cacheLimit = 20 * 1024 * 1024
        let hub = HubApi(downloadBase: rootURL)
        let configuration = ModelConfiguration(
            id: modelID,
            defaultPrompt: "Исправь текст"
        )

        progress("Qwen downloadModel started.")
        let modelDirectory = try await downloadModel(hub: hub, configuration: configuration) { progressValue in
            progress("Qwen download progress callback: \(progressValue)")
            downloadProgress(progressValue.fractionCompleted)
        }
        progress("Qwen downloadModel finished. modelDirectory=\(modelDirectory.path)")

        // Signal transition: files are on disk, now loading weights into memory (slow).
        onDownloadComplete()

        progress("Qwen loadModelContainer started.")
        let container = try await loadModelContainer(hub: hub, configuration: configuration) { progressValue in
            progress("Qwen load progress callback: \(progressValue)")
        }
        progress("Qwen loadModelContainer finished.")

        return (modelDirectory, container)
    }
}

func rewriteTextOnCPU(
    modelContainer: ModelContainer,
    inputText: String,
    locale: Locale,
    mode: RewriteMode,
    systemPromptOverride: String = "",
    log: @escaping @Sendable (String) -> Void
) async throws -> RewriteResultPayload {
    try await Device.withDefaultDevice(.cpu) {
        log("MLXTextRewriter CPU helper entered.")
        let startedAt = ContinuousClock.now

        let resolvedSystemPrompt = systemPromptOverride.isEmpty
            ? RewritePromptBuilder.systemPrompt(mode: mode, locale: locale)
            : systemPromptOverride
        let input = UserInput(chat: [
            .system(resolvedSystemPrompt),
            .user(RewritePromptBuilder.userPrompt(for: inputText))
        ])
        log("MLXTextRewriter preparing model input. sourceLength=\(inputText.count)")

        seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await modelContainer.prepare(input: input)
        log("MLXTextRewriter model input prepared.")
        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: GenerateParameters(maxTokens: 256, temperature: 0.2, topP: 0.95)
        )
        log("MLXTextRewriter generation stream opened.")

        var output = ""
        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                output += chunk
            case .info:
                break
            case .toolCall:
                break
            }
        }
        log("MLXTextRewriter generation finished. rawLength=\(output.count)")

        let rewritten = RewritePromptBuilder.sanitizeModelOutput(output)
        guard !rewritten.isEmpty else {
            throw AppFailure.rewriteFailed("The language model returned an empty response.")
        }
        log("MLXTextRewriter sanitized output length=\(rewritten.count)")

        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: rewritten,
            latency: startedAt.duration(to: .now)
        )
    }
}
