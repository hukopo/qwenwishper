@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import QwenWhisperApp

/// Plays an audio file into the live pipeline in real time, like a microphone would.
private final class FileAudioCapture: LiveAudioCapturing, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    private(set) var finished = false
    private let samples: [Float]
    private var feeder: Task<Void, Never>?

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        samples = LivePCMDownsampler().convert(buffer)
    }

    func start() async throws {
        let chunk = Int(LiveAudioCaptureSupport.targetSampleRate / 10)
        // Trailing silence lets the last words get decoded, as when the speaker pauses before stopping.
        let padded = samples + [Float](repeating: 0, count: chunk * 20)
        feeder = Task { [weak self] in
            for start in stride(from: 0, to: padded.count, by: chunk) {
                guard let self, !Task.isCancelled else { return }
                let slice = Array(padded[start ..< min(start + chunk, padded.count)])
                self.onSamples?(slice)
                self.onAudioLevel?(LiveAudioCaptureSupport.audioLevel(for: slice))
                try? await Task.sleep(for: .milliseconds(100))
            }
            self?.finished = true
        }
    }

    func stop() {
        feeder?.cancel()
    }
}

private actor UpdateLog {
    private(set) var updates: [(text: String, captureFinished: Bool)] = []
    func add(_ text: String, captureFinished: Bool) { updates.append((text, captureFinished)) }
}

private func normalized(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "ё", with: "е")
}

/// Real Whisper on real speech: downloads/loads the model, so it only runs when asked.
/// Run with: RUN_MODEL_TESTS=1 swift test --filter LiveTranscriptionAudio
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_MODEL_TESTS"] == "1"), .timeLimit(.minutes(15)))
func liveTranscriptionAudioShowsWordsWhileSpeakingAndEndsWithFullText() async throws {
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/live-ru.m4a")
    let capture = try FileAudioCapture(url: fixture)
    let service = RealtimeTranslationService(modelManager: ModelManager(), makeCapture: { _ in capture })
    let log = UpdateLog()

    try await service.start(
        configuration: .init(
            source: .microphone,
            targetLanguage: .original,
            whisperModelID: AppSettings.defaults.whisperModelID,
            qwenModelID: AppSettings.defaults.qwenModelID,
            updateInterval: .milliseconds(AppSettings.defaults.liveTranslationIntervalMs)
        ),
        onAudioLevel: { _ in },
        onUpdate: { update in
            let finished = capture.finished
            Task { await log.add(update.translatedText, captureFinished: finished) }
        }
    )

    // Wait for the audio to play out, then give the loop a moment to decode the tail.
    while !capture.finished { try await Task.sleep(for: .milliseconds(200)) }
    try await Task.sleep(for: .seconds(5))
    await service.stop()

    let updates = await log.updates
    let finalText = normalized(updates.last?.text ?? "")
    print("Live updates:\n" + updates.map { "  \($0.captureFinished ? "after " : "during") | \($0.text)" }.joined(separator: "\n"))

    #expect(updates.contains { !$0.captureFinished }, "no text was shown while the audio was still playing")
    for word in ["проверка", "погода", "парк"] {
        #expect(finalText.contains(word), "final text is missing \"\(word)\": \(finalText)")
    }
}
