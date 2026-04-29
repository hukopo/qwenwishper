import Foundation
import MLXLMCommon
@preconcurrency import WhisperBridge

private actor LiveAudioSampleStore {
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    func snapshot() -> [Float] {
        samples
    }

    func reset() {
        samples.removeAll(keepingCapacity: false)
    }

    func trim(confirmedSeconds: Double, overlapSeconds: Double) -> Int {
        let trimmedSeconds = max(0, confirmedSeconds - overlapSeconds)
        let trimmedSampleCount = min(samples.count, Int(trimmedSeconds * LiveAudioCaptureSupport.targetSampleRate))
        guard trimmedSampleCount > 0 else { return 0 }
        samples.removeFirst(trimmedSampleCount)
        return trimmedSampleCount
    }
}

actor RealtimeTranslationService: LiveTranslating {
    private let modelManager: ModelManager
    private let microphoneCapture = MicrophoneLiveCaptureService()
    private let systemAudioCapture = SystemAudioCaptureService()

    private var loopTask: Task<Void, Never>?
    private var activeSource: AudioInputSource?
    private var sampleStore = LiveAudioSampleStore()
    private var preparedWhisper: WhisperRuntimeBox?
    private var preparedQwen: ModelContainer?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func start(
        configuration: LiveTranslationConfiguration,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onUpdate: @escaping @Sendable (LiveTranslationUpdate) -> Void
    ) async throws {
        guard loopTask == nil else {
            throw AppFailure.alreadyBusy
        }

        var runtimeSettings = AppSettings.defaults
        runtimeSettings.whisperModelID = configuration.whisperModelID
        runtimeSettings.qwenModelID = configuration.qwenModelID
        runtimeSettings.qwenEnabled = true

        preparedWhisper = try await modelManager.liveWhisperRuntime(settings: runtimeSettings) { _ in }
        preparedQwen = configuration.targetLanguage.usesWhisperNativeTranslation
            ? nil
            : try await modelManager.prepareQwen(settings: runtimeSettings) { _ in }

        await sampleStore.reset()
        activeSource = configuration.source

        switch configuration.source {
        case .microphone:
            microphoneCapture.onSamples = { [sampleStore] samples in
                Task { await sampleStore.append(samples) }
            }
            microphoneCapture.onAudioLevel = onAudioLevel
            try microphoneCapture.start()
        case .systemAudio:
            systemAudioCapture.onSamples = { [sampleStore] samples in
                Task { await sampleStore.append(samples) }
            }
            systemAudioCapture.onAudioLevel = onAudioLevel
            try await systemAudioCapture.start()
        }

        loopTask = Task { [weak self] in
            await self?.runLoop(configuration: configuration, onUpdate: onUpdate)
        }
    }

    func stop() async {
        loopTask?.cancel()
        loopTask = nil

        switch activeSource {
        case .microphone:
            microphoneCapture.stop()
        case .systemAudio:
            systemAudioCapture.stop()
        case nil:
            break
        }

        microphoneCapture.onSamples = nil
        microphoneCapture.onAudioLevel = nil
        systemAudioCapture.onSamples = nil
        systemAudioCapture.onAudioLevel = nil
        activeSource = nil
        preparedWhisper = nil
        preparedQwen = nil
        await sampleStore.reset()
    }

    private func runLoop(
        configuration: LiveTranslationConfiguration,
        onUpdate: @escaping @Sendable (LiveTranslationUpdate) -> Void
    ) async {
        guard let whisper = preparedWhisper else {
            DiagnosticTrace.write("RealtimeTranslationService missing prepared Whisper runtime.")
            return
        }

        let qwenContainer = preparedQwen
        var lastBufferSize = 0
        var lastConfirmedSegmentEndSeconds: Float = 0
        var confirmedText = ""
        var lastPublishedTranscript = ""
        var latestTranslatedText = ""

        while !Task.isCancelled {
            do {
                let currentBuffer = await sampleStore.snapshot()
                let nextBufferSize = currentBuffer.count - lastBufferSize
                let nextBufferSeconds = Double(nextBufferSize) / LiveAudioCaptureSupport.targetSampleRate

                guard nextBufferSeconds >= configuration.updateInterval.secondsValue else {
                    try await Task.sleep(for: .milliseconds(120))
                    continue
                }

                lastBufferSize = currentBuffer.count

                let transcription = try await transcribeCurrentBuffer(
                    whisper: whisper,
                    samples: currentBuffer,
                    targetLanguage: configuration.targetLanguage,
                    lastConfirmedSegmentEndSeconds: lastConfirmedSegmentEndSeconds
                )

                let segments = transcription.segments
                let (nextConfirmedText, nextConfirmedSeconds, transcriptText) = mergeTranscript(
                    segments: segments,
                    currentConfirmedText: confirmedText,
                    currentConfirmedSeconds: lastConfirmedSegmentEndSeconds
                )
                confirmedText = nextConfirmedText
                lastConfirmedSegmentEndSeconds = nextConfirmedSeconds

                guard !transcriptText.isEmpty else {
                    try await Task.sleep(for: .milliseconds(120))
                    continue
                }

                if configuration.targetLanguage.usesWhisperNativeTranslation {
                    latestTranslatedText = transcriptText
                } else if transcriptText != lastPublishedTranscript, let qwenContainer {
                    let translation = try await translateText(
                        modelContainer: qwenContainer,
                        inputText: transcriptText,
                        targetLanguage: configuration.targetLanguage
                    ) { message in
                        DiagnosticTrace.write(message)
                    }
                    latestTranslatedText = translation.rewrittenText
                }

                lastPublishedTranscript = transcriptText
                onUpdate(.init(
                    transcriptText: transcriptText,
                    translatedText: latestTranslatedText.isEmpty ? transcriptText : latestTranslatedText,
                    isFinal: false
                ))

                let trimmedSampleCount = await sampleStore.trim(
                    confirmedSeconds: Double(lastConfirmedSegmentEndSeconds),
                    overlapSeconds: 1
                )
                if trimmedSampleCount > 0 {
                    let trimmedSeconds = Float(trimmedSampleCount) / Float(LiveAudioCaptureSupport.targetSampleRate)
                    lastBufferSize = max(0, lastBufferSize - trimmedSampleCount)
                    lastConfirmedSegmentEndSeconds = max(0, lastConfirmedSegmentEndSeconds - trimmedSeconds)
                }
            } catch {
                DiagnosticTrace.write("Realtime translation loop error: \(error.localizedDescription)")
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func transcribeCurrentBuffer(
        whisper: WhisperRuntimeBox,
        samples: [Float],
        targetLanguage: TranslationTargetLanguage,
        lastConfirmedSegmentEndSeconds: Float
    ) async throws -> TranscriptionResult {
        var options = DecodingOptions(
            task: targetLanguage.usesWhisperNativeTranslation ? .translate : .transcribe,
            language: nil,
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: true,
            withoutTimestamps: true,
            wordTimestamps: true,
            concurrentWorkerCount: 4
        )
        options.clipTimestamps = [lastConfirmedSegmentEndSeconds]

        let results = try await whisper.value.transcribe(audioArray: samples, decodeOptions: options)
        return TranscriptionUtilities.mergeTranscriptionResults(results)
    }

    private func mergeTranscript(
        segments: [TranscriptionSegment],
        currentConfirmedText: String,
        currentConfirmedSeconds: Float
    ) -> (confirmedText: String, confirmedSeconds: Float, transcript: String) {
        var confirmedText = currentConfirmedText
        var confirmedSeconds = currentConfirmedSeconds

        if segments.count > 2 {
            let confirmedSegments = Array(segments.prefix(segments.count - 2))
            let appendable = confirmedSegments.filter { $0.end > currentConfirmedSeconds }
            if let lastSegment = appendable.last {
                let appendedText = appendable
                    .map(\.text)
                    .joined(separator: " ")
                    .collapsingWhitespace()
                if !appendedText.isEmpty {
                    confirmedText = [confirmedText, appendedText]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .collapsingWhitespace()
                }
                confirmedSeconds = lastSegment.end
            }
            let draftText = segments
                .suffix(2)
                .map(\.text)
                .joined(separator: " ")
                .collapsingWhitespace()
            let transcript = [confirmedText, draftText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .collapsingWhitespace()
            return (confirmedText, confirmedSeconds, transcript)
        }

        let draftText = segments
            .map(\.text)
            .joined(separator: " ")
            .collapsingWhitespace()
        let transcript = [confirmedText, draftText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .collapsingWhitespace()
        return (confirmedText, confirmedSeconds, transcript)
    }
}
