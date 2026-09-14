import Foundation

protocol SpeechTranscribing: Sendable {
    func transcribe(audio: Data) async throws -> String
}
