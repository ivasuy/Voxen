import AVFoundation

/// The tap owns PCM conversion; a lock protects snapshots read from the main thread.
final class AudioLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()
    private var level: Float = 0
    private var sampleCount = 0
    private let maxSamples: Int

    init(sampleRate: Double) { maxSamples = Int(sampleRate * 120) }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }
        var pcm = [Int16](repeating: 0, count: frames)
        var sum: Float = 0
        for index in 0..<frames {
            var value: Float = 0
            for channel in 0..<channelCount { value += channels[channel][index] }
            value /= Float(channelCount)
            if !value.isFinite { value = 0 }
            sum += value * value
            pcm[index] = Int16(max(-1, min(1, value)) * Float(Int16.max)).littleEndian
        }
        lock.lock()
        defer { lock.unlock() }
        level = min(1, sqrt(sum / Float(frames)) * 7)
        let accepted = min(frames, maxSamples - sampleCount)
        if accepted > 0 {
            pcm.withUnsafeBytes { samples.append(contentsOf: $0.prefix(accepted * 2)) }
            sampleCount += accepted
        }
    }

    var currentLevel: Float {
        lock.lock(); defer { lock.unlock() }
        return level
    }

    func wav(sampleRate: Double) -> Data {
        lock.lock(); defer { lock.unlock() }
        return Self.encodeWAV(pcm: samples, sampleRate: UInt32(sampleRate))
    }

    static func encodeWAV(pcm: Data, sampleRate: UInt32) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + pcm.count)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(sampleRate); number(sampleRate * 2); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
