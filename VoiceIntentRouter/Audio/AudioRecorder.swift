import AVFoundation
import os

@MainActor
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var capture: AudioLevelMonitor?
    private var sampleRate: Double = 0
    private(set) var isRecording = false
    private let log = Logger(subsystem: "dev.voiceintent.router", category: "Audio")
    var level: Float { capture?.currentLevel ?? 0 }

    func start() throws {
        guard !isRecording else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RouterError.message("Allow Microphone access in Settings before recording.")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw RouterError.message("No compatible microphone is available. Check Sound settings.")
        }
        sampleRate = format.sampleRate
        let capture = AudioLevelMonitor(sampleRate: sampleRate)
        self.capture = capture
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in capture.append(buffer) }
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            log.info("Recording started")
        } catch {
            input.removeTap(onBus: 0)
            self.capture = nil
            throw RouterError.message("Microphone could not start. Check the selected audio device.")
        }
    }

    func stop() throws -> Data {
        guard isRecording else { throw RouterError.message("No recording is in progress.") }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        let audio = capture?.wav(sampleRate: sampleRate) ?? Data()
        capture = nil
        log.info("Recording stopped; \(audio.count) bytes")
        guard audio.count > 44 + Int(sampleRate * 0.2) * 2 else {
            throw RouterError.message("Recording was too short. Press Option–Space and speak for a moment.")
        }
        return audio
    }

    func cancel() {
        if isRecording { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        isRecording = false
        capture = nil
    }
}
