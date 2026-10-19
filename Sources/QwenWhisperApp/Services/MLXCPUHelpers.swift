import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// Loads the Qwen model container. Uses the MLX default device (GPU/Metal on Apple Silicon).
/// Whisper runs on CoreML/Neural Engine and does not compete for the same compute units,
/// so there is no reason to force CPU here.
func loadQwenContainer(
    rootURL: URL,
    modelID: String,
    downloadProgress: @escaping @Sendable (Double) -> Void = { _ in },
    /// Called after all model files are present on disk but before weights are loaded into memory.
    /// Use this to transition the UI from "downloading…" to "loading…".
    onDownloadComplete: @escaping @Sendable () -> Void = {},
    progress: @escaping @Sendable (String) -> Void
) async throws -> (modelDirectory: URL, container: ModelContainer) {
    progress("Qwen loader entered.")
    let downloader = #hubDownloader(HubClient(cache: HubCache(cacheDirectory: rootURL.appendingPathComponent("hub"))))

    progress("Qwen download started.")
    let modelDirectory = try await downloader.download(
        id: modelID,
        revision: nil,
        matching: ["*.safetensors", "*.json", "*.jinja", "*.txt"],
        useLatest: false
    ) { progressValue in
        downloadProgress(progressValue.fractionCompleted)
    }
    progress("Qwen download finished. modelDirectory=\(modelDirectory.path)")

    // Signal transition: files are on disk, now loading weights into memory (slow).
    onDownloadComplete()

    progress("Qwen loadModelContainer started.")
    let container = try await loadModelContainer(from: modelDirectory, using: #huggingFaceTokenizerLoader())
    progress("Qwen loadModelContainer finished.")

    return (modelDirectory, container)
}

/// Rewrites text using the loaded Qwen model container.
/// Runs on the MLX default device (GPU/Metal on Apple Silicon).
func rewriteText(
    modelContainer: ModelContainer,
    inputText: String,
    locale: Locale,
    mode: RewriteMode,
    systemPromptOverride: String = "",
    log: @escaping @Sendable (String) -> Void
) async throws -> RewriteResultPayload {
    log("MLXTextRewriter entered.")
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
        output += generation.chunk ?? ""
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

func translateText(
    modelContainer: ModelContainer,
    inputText: String,
    targetLanguage: TranslationTargetLanguage,
    log: @escaping @Sendable (String) -> Void
) async throws -> RewriteResultPayload {
    log("MLXTextTranslator entered.")
    let startedAt = ContinuousClock.now

    let systemPrompt = """
    You are a live interpreter.
    Translate the user's text into \(targetLanguage.promptName).
    Preserve meaning, tone, names, and numbers.
    Return only the translation.
    """

    let input = UserInput(chat: [
        .system(systemPrompt),
        .user(inputText)
    ])
    log("MLXTextTranslator preparing model input. sourceLength=\(inputText.count)")

    seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
    let lmInput = try await modelContainer.prepare(input: input)
    let maxTokens = max(96, min(512, inputText.count * 2))
    let stream = try await modelContainer.generate(
        input: lmInput,
        parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2, topP: 0.8)
    )

    var output = ""
    for await generation in stream {
        output += generation.chunk ?? ""
    }

    let translated = RewritePromptBuilder.sanitizeModelOutput(output)
    guard !translated.isEmpty else {
        throw AppFailure.translationFailed("The translation model returned an empty response.")
    }

    return RewriteResultPayload(
        sourceText: inputText,
        rewrittenText: translated,
        latency: startedAt.duration(to: .now)
    )
}
