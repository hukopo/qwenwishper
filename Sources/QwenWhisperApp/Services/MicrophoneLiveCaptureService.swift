import AVFoundation
import Foundation

final class MicrophoneLiveCaptureService: NSObject, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?

    private var engine: AVAudioEngine?
    private let downsampler = LivePCMDownsampler()

    func start() throws {
        guard engine == nil else {
            throw AppFailure.alreadyBusy
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        let samples = downsampler.convert(buffer)
        guard !samples.isEmpty else { return }
        onSamples?(samples)
        onAudioLevel?(LiveAudioCaptureSupport.audioLevel(for: samples))
    }
}
