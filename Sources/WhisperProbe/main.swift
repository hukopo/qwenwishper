import Foundation
@preconcurrency import WhisperBridge

@main
struct WhisperProbe {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: WhisperProbe <audio-path> [model-id]\n".utf8))
            throw ExitCode.failure
        }

        let audioPath = CommandLine.arguments[1]
        let modelID = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "base"
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QwenWhisper/Models/whisper-downloads", isDirectory: true)

        print("audio: \(audioPath)")
        print("model: \(modelID)")
        print("downloadBase: \(cacheRoot.path)")

        let whisper = try await WhisperKit(
            WhisperKitConfig(
                model: modelID,
                downloadBase: cacheRoot,
                modelRepo: "argmaxinc/whisperkit-coreml",
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: true
            )
        )

        let attempts: [(String, DecodingOptions)] = [
            (
                "primary",
                DecodingOptions(
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
            ),
            (
                "relaxed-ru",
                DecodingOptions(
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
            ),
            (
                "detect-language",
                DecodingOptions(
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
            )
        ]

        for (label, options) in attempts {
            print("== \(label) ==")
            let results = try await whisper.transcribe(audioPath: audioPath, decodeOptions: options)
            let merged = TranscriptionUtilities.mergeTranscriptionResults(results)
            let text = merged.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let segmentCount = results.reduce(into: 0) { $0 += $1.segments.count }
            print("windows: \(results.count)")
            print("segments: \(segmentCount)")
            print("language: \(merged.language)")
            if let first = results.first?.segments.first {
                print("first.noSpeechProb: \(first.noSpeechProb)")
                print("first.avgLogprob: \(first.avgLogprob)")
                print("first.text: \(first.text)")
            } else {
                print("first: <none>")
            }
            print("text: \(text)")
        }
    }
}

enum ExitCode: Error {
    case failure
}
