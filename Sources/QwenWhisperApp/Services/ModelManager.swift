import CryptoKit
import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
@preconcurrency import WhisperBridge

struct ModelAvailability: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case idle
        /// Model is warming up (CoreML compilation, initial load).
        case loading
        /// Model is actively processing: Whisper is transcribing, Qwen is rewriting.
        case processing
        /// Associated value is download fraction 0.0–1.0, or 0 if unknown.
        case downloading(Double)
        case ready
        case failed(String)
    }

    var whisper: State = .idle
    var qwen: State = .idle
}

private final class WhisperRuntimeBox: @unchecked Sendable {
    let value: WhisperKit

    init(value: WhisperKit) {
        self.value = value
    }
}

private struct ModelFingerprint: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var relativePath: String
        var byteCount: Int64
        var sha256: String
    }

    var entries: [Entry]
}

actor ModelManager: ModelRuntimeManaging {
    private let fileManager: FileManager
    private let rootURL: URL
    private var whisperKit: WhisperRuntimeBox?
    private var qwenContainer: ModelContainer?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QwenWhisper/Models", isDirectory: true)
    }

    func resetAll() throws {
        whisperKit = nil
        qwenContainer = nil
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    func cachedAvailability(settings: AppSettings) -> ModelAvailability {
        var availability = ModelAvailability()

        let whisperFingerprint = rootURL.appendingPathComponent("whisper-\(safeFileName(settings.whisperModelID)).json")
        if fileManager.fileExists(atPath: whisperFingerprint.path) || existingWhisperDirectory(settings: settings) != nil {
            availability.whisper = .ready
        }

        let qwenFingerprint = rootURL.appendingPathComponent("qwen-\(safeFileName(settings.qwenModelID)).json")
        if fileManager.fileExists(atPath: qwenFingerprint.path) {
            availability.qwen = .ready
        }

        return availability
    }

    func preloadWhisperIfCached(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async {
        // Only warm up if there is something already on disk — never trigger a download.
        guard existingWhisperDirectory(settings: settings) != nil
                || fileManager.fileExists(atPath: rootURL.appendingPathComponent("whisper-\(safeFileName(settings.whisperModelID)).json").path)
        else {
            DiagnosticTrace.write("Whisper preload skipped — model not cached.")
            return
        }
        DiagnosticTrace.write("Whisper preload started in background.")
        try? await prepareWhisper(settings: settings, progress: progress)
    }

    func retryWhisper(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async {
        DiagnosticTrace.write("Retrying Whisper model \(settings.whisperModelID).")
        // Clear the in-memory runtime so prepareWhisper will re-initialize.
        whisperKit = nil
        // Remove the model directory so WhisperKit re-downloads it from scratch.
        if let existingDir = existingWhisperDirectory(settings: settings) {
            try? fileManager.removeItem(at: existingDir)
            DiagnosticTrace.write("Removed Whisper directory: \(existingDir.lastPathComponent).")
        }
        // Remove the fingerprint so cachedAvailability shows the model as absent.
        let fp = rootURL.appendingPathComponent("whisper-\(safeFileName(settings.whisperModelID)).json")
        try? fileManager.removeItem(at: fp)

        do {
            try await prepareWhisper(settings: settings, progress: progress)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DiagnosticTrace.write("Whisper retry failed: \(message)")
            progress(.failed(message))
        }
    }

    func retryQwen(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async {
        DiagnosticTrace.write("Retrying Qwen model \(settings.qwenModelID).")
        // Clear the in-memory container so prepareQwen will re-initialize.
        qwenContainer = nil
        // Remove the fingerprint so prepareQwen treats the model as not yet downloaded.
        let fp = rootURL.appendingPathComponent("qwen-\(safeFileName(settings.qwenModelID)).json")
        try? fileManager.removeItem(at: fp)

        do {
            _ = try await prepareQwen(settings: settings, progress: progress)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DiagnosticTrace.write("Qwen retry failed: \(message)")
            progress(.failed(message))
        }
    }

    func prepareWhisper(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async throws {
        if whisperKit != nil {
            DiagnosticTrace.write("Whisper runtime already initialized for model \(settings.whisperModelID).")
            progress(.ready)
            return
        }

        let existingFolder = existingWhisperDirectory(settings: settings)
        progress(existingFolder != nil ? .loading : .downloading(0))
        DiagnosticTrace.write("Preparing Whisper runtime for model \(settings.whisperModelID).")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let whisperDownloadBase = rootURL.appendingPathComponent("whisper-downloads", isDirectory: true)

        // Download phase (skipped if model folder already exists on disk).
        let modelFolder: URL
        if let existing = existingFolder {
            modelFolder = existing
        } else {
            modelFolder = try await downloadWhisperModel(
                modelID: settings.whisperModelID,
                downloadBase: whisperDownloadBase,
                onProgress: { fraction in progress(.downloading(fraction)) }
            )
        }

        // Load + prewarm phase (CoreML compilation).
        progress(.loading)
        let whisper = try await loadWhisperRuntime(modelFolder: modelFolder)

        if let modelFolderFromKit = whisper.value.modelFolder {
            try persistFingerprint(for: modelFolderFromKit, key: "whisper-\(settings.whisperModelID)")
        }

        whisperKit = whisper
        DiagnosticTrace.write("Whisper runtime ready. modelFolder=\(whisper.value.modelFolder?.path ?? "nil")")
        progress(.ready)
    }

    func transcribe(audioURL: URL, settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async throws -> TranscriptionResultPayload {
        try await prepareWhisper(settings: settings, progress: progress)
        guard let whisperKit else {
            throw AppFailure.transcriptionFailed("WhisperKit was not initialized.")
        }

        let startedAt = ContinuousClock.now
        let primaryOptions = DecodingOptions(
            task: .transcribe,
            language: "ru",
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: 4
        )

        DiagnosticTrace.write("Starting Whisper transcription for \(audioURL.lastPathComponent).")
        let primaryText = try await transcribeText(
            whisperKit: whisperKit.value,
            audioURL: audioURL,
            options: primaryOptions,
            label: "primary"
        )

        let fallbackText: String
        if primaryText.isEmpty {
            let relaxedOptions = DecodingOptions(
                task: .transcribe,
                language: "ru",
                temperature: 0,
                temperatureFallbackCount: 4,
                usePrefillPrompt: true,
                detectLanguage: false,
                withoutTimestamps: true,
                wordTimestamps: false,
                compressionRatioThreshold: nil,
                logProbThreshold: nil,
                firstTokenLogProbThreshold: nil,
                noSpeechThreshold: nil,
                concurrentWorkerCount: 4
            )
            fallbackText = try await transcribeText(
                whisperKit: whisperKit.value,
                audioURL: audioURL,
                options: relaxedOptions,
                label: "relaxed-ru"
            )
        } else {
            fallbackText = primaryText
        }

        let finalText: String
        if fallbackText.isEmpty {
            let detectOptions = DecodingOptions(
                task: .transcribe,
                language: nil,
                temperature: 0,
                temperatureFallbackCount: 4,
                usePrefillPrompt: false,
                detectLanguage: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                compressionRatioThreshold: nil,
                logProbThreshold: nil,
                firstTokenLogProbThreshold: nil,
                noSpeechThreshold: nil,
                concurrentWorkerCount: 4
            )
            finalText = try await transcribeText(
                whisperKit: whisperKit.value,
                audioURL: audioURL,
                options: detectOptions,
                label: "detect-language"
            )
        } else {
            finalText = fallbackText
        }

        guard !finalText.isEmpty else {
            DiagnosticTrace.write("Whisper transcription produced empty text after all attempts.")
            throw AppFailure.emptySpeech
        }

        let logText = finalText.replacingOccurrences(of: "\n", with: "\\n")
        DiagnosticTrace.write("Whisper transcription succeeded. length=\(finalText.count) text=\(logText)")

        return TranscriptionResultPayload(
            text: finalText,
            latency: startedAt.duration(to: .now),
            audioURL: audioURL
        )
    }

    func prepareQwen(settings: AppSettings, progress: @escaping @Sendable (ModelAvailability.State) -> Void) async throws -> ModelContainer {
        if let qwenContainer {
            DiagnosticTrace.write("Qwen container already initialized for model \(settings.qwenModelID).")
            progress(.ready)
            return qwenContainer
        }

        if let preflightFailure = qwenRuntimePreflightFailure() {
            DiagnosticTrace.write("Qwen runtime preflight failed: \(preflightFailure)")
            progress(.failed(preflightFailure))
            throw AppFailure.rewriteFailed(preflightFailure)
        }

        progress(existingQwenFingerprint(settings: settings) ? .loading : .downloading(0))
        DiagnosticTrace.write("Preparing Qwen container for model \(settings.qwenModelID).")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let rootURL = self.rootURL
        let modelID = settings.qwenModelID
        let loaded = try await loadQwenContainerOnCPU(
            rootURL: rootURL,
            modelID: modelID,
            downloadProgress: { fraction in progress(.downloading(fraction)) }
        ) { message in
            DiagnosticTrace.write(message)
        }
        let modelDirectory = loaded.modelDirectory
        try persistFingerprint(for: modelDirectory, key: "qwen-\(settings.qwenModelID)")
        let container = loaded.container
        qwenContainer = container
        progress(.ready)
        return container
    }

    private func persistFingerprint(for directory: URL, key: String) throws {
        let fingerprint = try buildFingerprint(for: directory)
        let fingerprintURL = rootURL.appendingPathComponent("\(safeFileName(key)).json")
        let data = try JSONEncoder().encode(fingerprint)
        try data.write(to: fingerprintURL, options: .atomic)
    }

    private func buildFingerprint(for directory: URL) throws -> ModelFingerprint {
        guard fileManager.fileExists(atPath: directory.path) else {
            throw AppFailure.modelDownloadFailed("Model directory missing at \(directory.path)")
        }

        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [ModelFingerprint.Entry] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }

            let data = try Data(contentsOf: fileURL)
            let digest = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
            entries.append(.init(relativePath: relativePath, byteCount: Int64(values.fileSize ?? 0), sha256: digest))
        }

        if entries.isEmpty {
            throw AppFailure.modelDownloadFailed("Downloaded model folder is empty.")
        }

        return ModelFingerprint(entries: entries.sorted { $0.relativePath < $1.relativePath })
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
    }

    private func existingWhisperDirectory(settings: AppSettings) -> URL? {
        let explicit = rootURL
            .appendingPathComponent("whisper-downloads/models/argmaxinc/whisperkit-coreml/openai_whisper-\(settings.whisperModelID)")
        if fileManager.fileExists(atPath: explicit.path) {
            return explicit
        }

        return nil
    }

    private func existingQwenFingerprint(settings: AppSettings) -> Bool {
        let qwenFingerprint = rootURL.appendingPathComponent("qwen-\(safeFileName(settings.qwenModelID)).json")
        return fileManager.fileExists(atPath: qwenFingerprint.path)
    }

    private func qwenRuntimePreflightFailure() -> String? {
        let executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        let executableDirectory = executableURL.deletingLastPathComponent()
        let candidatePaths = [
            executableDirectory.appendingPathComponent("default.metallib").path,
            executableDirectory.appendingPathComponent("mlx.metallib").path,
            executableDirectory.appendingPathComponent("Resources/default.metallib").path,
            executableDirectory.appendingPathComponent("Resources/mlx.metallib").path,
        ]

        if candidatePaths.contains(where: { fileManager.fileExists(atPath: $0) }) {
            return nil
        }

        return "MLX Metal shaders not found (mlx.metallib missing next to executable). Run scripts/run-dev.sh to auto-download them."
    }

    /// Downloads the Whisper model variant from HuggingFace and returns the local folder URL.
    nonisolated private func downloadWhisperModel(
        modelID: String,
        downloadBase: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: modelID,
            downloadBase: downloadBase,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { p in onProgress(p.fractionCompleted) }
        )
    }

    /// Loads an already-downloaded Whisper model folder into memory and prewarns it.
    nonisolated private func loadWhisperRuntime(modelFolder: URL) async throws -> WhisperRuntimeBox {
        let whisper = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: modelFolder.path,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: false
            )
        )
        return WhisperRuntimeBox(value: whisper)
    }

    nonisolated private func transcribeText(
        whisperKit: WhisperKit,
        audioURL: URL,
        options: DecodingOptions,
        label: String
    ) async throws -> String {
        DiagnosticTrace.write(
            "Whisper attempt \(label) started. language=\(options.language ?? "auto") usePrefill=\(options.usePrefillPrompt) detectLanguage=\(options.detectLanguage) noSpeechThreshold=\(options.noSpeechThreshold.map(String.init(describing:)) ?? "nil")"
        )

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let merged = TranscriptionUtilities.mergeTranscriptionResults(results)
        let text = merged.text.collapsingWhitespace()
        let segmentCount = results.reduce(into: 0) { $0 += $1.segments.count }
        let firstSegment = results.first?.segments.first
        let firstSegmentSummary: String
        if let firstSegment {
            firstSegmentSummary = "firstSegmentText=\(firstSegment.text.collapsingWhitespace().prefix(80)) avgLogProb=\(firstSegment.avgLogprob) noSpeechProb=\(firstSegment.noSpeechProb)"
        } else {
            firstSegmentSummary = "no segments"
        }

        DiagnosticTrace.write(
            "Whisper attempt \(label) finished. windows=\(results.count) segments=\(segmentCount) mergedLength=\(text.count) language=\(merged.language) \(firstSegmentSummary)"
        )

        return text
    }
}
