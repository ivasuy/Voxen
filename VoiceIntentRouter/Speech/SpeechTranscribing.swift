import Foundation

protocol SpeechTranscribing {
    func transcribe(audio: Data) async throws -> String
}
