import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?

    private let sampleHandlerQueue = DispatchQueue(label: "qwenwhisper.system-audio.samples")
    private let downsampler = LivePCMDownsampler()
    private var stream: SCStream?

    func start() async throws {
        guard stream == nil else {
            throw AppFailure.alreadyBusy
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AppFailure.transcriptionFailed("No display is available for system-audio capture.")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.capturesAudio = true
        configuration.sampleRate = Int(LiveAudioCaptureSupport.targetSampleRate)
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task {
            try? await stream.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DiagnosticTrace.write("SystemAudioCaptureService stream stopped: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                      let format = AVAudioFormat(
                          standardFormatWithSampleRate: description.mSampleRate,
                          channels: description.mChannelsPerFrame
                      ),
                      let pcmBuffer = AVAudioPCMBuffer(
                          pcmFormat: format,
                          bufferListNoCopy: audioBufferList.unsafePointer
                      )
                else {
                    return
                }

                let samples = downsampler.convert(pcmBuffer)
                guard !samples.isEmpty else { return }
                onSamples?(samples)
                onAudioLevel?(LiveAudioCaptureSupport.audioLevel(for: samples))
            }
        } catch {
            DiagnosticTrace.write("SystemAudioCaptureService sample conversion failed: \(error.localizedDescription)")
        }
    }
}
