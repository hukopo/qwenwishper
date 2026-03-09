import AVFoundation
import Foundation

final class AudioCaptureService: NSObject, AudioCapturing, @unchecked Sendable {
    struct Recording {
        let url: URL
        let durationSeconds: TimeInterval
    }

    var onAudioLevel: ((Float) -> Void)?

    private let fileManager: FileManager
    private let recordingsDirectory: URL
    private var recorder: AVAudioRecorder?
    private var activeURL: URL?
    private var stopTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var meterTimer: Timer?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.recordingsDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QwenWhisper/Recordings", isDirectory: true)
    }

    func startRecording(maxDuration: Duration, onMaxDurationReached: @escaping @Sendable () -> Void) throws {
        guard recorder == nil else {
            throw AppFailure.alreadyBusy
        }

        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let targetURL = recordingsDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let recorder = try AVAudioRecorder(url: targetURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AppFailure.transcriptionFailed("Failed to start the audio recorder.")
        }

        DiagnosticTrace.write("AudioCaptureService started recording to \(targetURL.path).")

        self.recorder = recorder
        self.activeURL = targetURL
        self.recordingStartedAt = Date()

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            self.onAudioLevel?(level)
        }

        stopTask = Task {
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            DiagnosticTrace.write("AudioCaptureService max duration reached.")
            onMaxDurationReached()
        }
    }

    func stopRecording() throws -> Recording {
        guard let recorder, let activeURL else {
            throw AppFailure.recordingNotActive
        }

        stopTask?.cancel()
        stopTask = nil
        meterTimer?.invalidate()
        meterTimer = nil

        recorder.stop()
        self.recorder = nil
        self.activeURL = nil

        let recorderDuration = recorder.currentTime
        let fileDuration = Self.fileDurationSeconds(for: activeURL)
        let wallClockDuration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        let resolvedDuration = max(fileDuration, recorderDuration, wallClockDuration)
        let recording = Recording(url: activeURL, durationSeconds: resolvedDuration)
        let byteCount = (try? fileManager.attributesOfItem(atPath: activeURL.path)[.size] as? NSNumber)?.intValue ?? 0
        DiagnosticTrace.write(
            """
            AudioCaptureService stopped recording. file=\(activeURL.lastPathComponent) resolvedDuration=\(String(format: "%.2f", recording.durationSeconds))s recorderCurrentTime=\(String(format: "%.2f", recorderDuration))s fileDuration=\(String(format: "%.2f", fileDuration))s wallClockDuration=\(String(format: "%.2f", wallClockDuration))s size=\(byteCount) bytes.
            """
        )
        return recording
    }

    func cancelRecording() {
        stopTask?.cancel()
        stopTask = nil
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        DiagnosticTrace.write("AudioCaptureService cancelled recording.")
        recorder = nil
        activeURL = nil
        recordingStartedAt = nil
    }

    private static func fileDurationSeconds(for url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return 0
        }

        let format = audioFile.processingFormat
        guard format.sampleRate > 0 else {
            return 0
        }

        return Double(audioFile.length) / format.sampleRate
    }
}
