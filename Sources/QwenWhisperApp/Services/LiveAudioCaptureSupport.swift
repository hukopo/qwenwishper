@preconcurrency import AVFoundation
import Foundation

enum LiveAudioCaptureSupport {
    static let targetSampleRate = 16_000.0

    static func makeTargetFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    static func audioLevel(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -160 }
        let rms = sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count))
        guard rms > 0 else { return -160 }
        return max(-160, 20 * log10(rms))
    }
}

final class LivePCMDownsampler {
    private var converter: AVAudioConverter?
    private var lastInputSignature = ""

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let inputFormat = buffer.format
        if canUseBufferDirectly(inputFormat) {
            return Self.extractSamples(from: buffer)
        }

        let signature = [
            String(inputFormat.sampleRate),
            String(inputFormat.channelCount),
            String(describing: inputFormat.commonFormat),
            String(inputFormat.isInterleaved),
        ].joined(separator: "|")

        if converter == nil || lastInputSignature != signature {
            converter = AVAudioConverter(from: inputFormat, to: LiveAudioCaptureSupport.makeTargetFormat())
            lastInputSignature = signature
        }

        guard let converter else {
            return []
        }

        let ratio = LiveAudioCaptureSupport.targetSampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 64)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: LiveAudioCaptureSupport.makeTargetFormat(),
            frameCapacity: max(capacity, 64)
        ) else {
            return []
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else {
            return []
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return Self.extractSamples(from: outputBuffer)
        case .error:
            return []
        @unknown default:
            return []
        }
    }

    private func canUseBufferDirectly(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && !format.isInterleaved
            && format.channelCount == 1
            && abs(format.sampleRate - LiveAudioCaptureSupport.targetSampleRate) < 0.5
    }

    private static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?.pointee else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
