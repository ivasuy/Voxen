import Foundation
@preconcurrency import os

struct AssemblyAIService: SpeechTranscribing {
    let apiKey: String
    var client = APIClient()
    var pollInterval: Duration = .seconds(1)
    var timeout: Duration = .seconds(90)
    private let baseURL = URL(string: "https://api.assemblyai.com/v2/")!
    private let log = Logger(subsystem: "dev.voiceintent.router", category: "AssemblyAI")

    private struct Upload: Decodable { let upload_url: String }
    private struct Transcript: Decodable {
        let id: String
        let status: String
        let text: String?
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue(path == "upload" ? "application/octet-stream" : "application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func transcribe(audio: Data) async throws -> String {
        guard !apiKey.isEmpty else { throw RouterError.message("Add your AssemblyAI API key in Settings.") }
        log.info("Transcription upload requested")
        let uploaded = try await client.send(request("upload", method: "POST", body: audio), service: "AssemblyAI")
        let upload = try JSONDecoder().decode(Upload.self, from: uploaded)
        let body = try JSONSerialization.data(withJSONObject: [
            "audio_url": upload.upload_url,
            "speech_models": ["universal-3-pro", "universal-2"],
            "language_code": "en"
        ])
        let submitted = try await client.send(request("transcript", method: "POST", body: body), service: "AssemblyAI")
        var transcript = try JSONDecoder().decode(Transcript.self, from: submitted)
        let id = transcript.id
        do {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while true {
                try Task.checkCancellation()
                if transcript.status == "completed" {
                    let result = transcript.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !result.isEmpty else { throw RouterError.message("No speech was detected. Try again closer to the microphone.") }
                    log.info("Transcript received; \(result.count) characters")
                    await deleteTranscript(id)
                    return result
                }
                if transcript.status == "error" { throw RouterError.message("AssemblyAI could not transcribe this recording. Try again.") }
                guard ContinuousClock.now < deadline else { throw RouterError.message("AssemblyAI transcription timed out. Try a shorter recording.") }
                try await Task.sleep(for: pollInterval)
                let data = try await client.send(request("transcript/\(id)"), service: "AssemblyAI")
                transcript = try JSONDecoder().decode(Transcript.self, from: data)
            }
        } catch {
            await deleteTranscript(id)
            throw error
        }
    }

    private func deleteTranscript(_ id: String) async {
        // Separate task allows best-effort cleanup even after the voice request was cancelled.
        var cleanupRequest = request("transcript/\(id)", method: "DELETE")
        cleanupRequest.timeoutInterval = 3
        let cleanup = cleanupRequest
        let client = client
        let success = await Task.detached {
            (try? await client.send(cleanup, service: "AssemblyAI cleanup")) != nil
        }.value
        if !success { log.warning("Remote transcript cleanup failed; provider retention applies") }
    }
}
