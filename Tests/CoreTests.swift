import Foundation
import AVFoundation
import AppKit
import ApplicationServices

struct FixtureProvider: LLMProvider {
    let respond: (String, String) throws -> String
    func generate(instructions: String, input: String) async throws -> String { try respond(instructions, input) }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    static var responseHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let headers = ["Content-Type": "application/json"].merging(Self.responseHeaders) { _, new in new }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class MemoryClipboard: GeneratedTextWriting {
    var string: String

    init(_ string: String) {
        self.string = string
    }

    func copy(_ generated: GeneratedText) throws {
        let cleaned = ClipboardOutput.clean(generated.text)
        guard !cleaned.isEmpty else { throw RouterError.message("The model returned no usable text.") }
        string = cleaned
    }
}

@main
struct CoreTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: \(message)") }
        checks += 1
    }

    @MainActor static func testResponseHistory() async throws {
        let suite = "dev.voxen.history-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ResponseHistory(defaults: defaults)
        check(history.entries.isEmpty && history.isEnabled, "History initially empty and enabled")
        let result = try await IntentTransformer(provider: FixtureProvider { _, _ in "Tomorrow morning works." })
            .transform(VoiceContext(appName: "Chrome", bundleIdentifier: nil, mode: .messaging,
                                    selectedText: "Private source fixture", transcript: "Private spoken fixture"))
        history.append(result, appName: "Chrome", websiteHost: "mail.example.test", mode: .messaging)
        check(history.entries.first?.text == result.text, "History stores generated output")
        check(history.entries.first?.source == "mail.example.test", "History labels website source")
        let encoded = String(decoding: defaults.data(forKey: "responseHistory.v1")!, as: UTF8.self)
        check(!encoded.contains("Private source fixture") && !encoded.contains("Private spoken fixture"), "History excludes source selection and transcript")
        check(ResponseHistory(defaults: defaults).entries == history.entries, "History survives store reload")
        history.isEnabled = false
        history.append(result, appName: "Ignored", websiteHost: nil, mode: .generic)
        check(history.entries.count == 1, "Disabled history does not append")
        check(!ResponseHistory(defaults: defaults).isEnabled, "History preference persists")
        history.isEnabled = true
        for _ in 0..<105 { history.append(result, appName: "Cursor", websiteHost: nil, mode: .coding) }
        check(history.entries.count == 100, "History bounded to last 100")
        check(history.entries.first?.source == "Cursor", "Native source falls back to app name")
        let id = history.entries[0].id
        history.remove(id)
        check(history.entries.count == 99 && !history.entries.contains { $0.id == id }, "Delete individual response")
        check(ResponseHistory(defaults: defaults).entries.count == 99, "Deletion persists")
        history.clear()
        check(history.entries.isEmpty && defaults.data(forKey: "responseHistory.v1") == nil, "Clear removes stored history")
        defaults.set(Data("bad JSON".utf8), forKey: "responseHistory.v1")
        check(ResponseHistory(defaults: defaults).entries.isEmpty, "Invalid stored history does not crash")
    }

    @MainActor static func testGeminiResearch() async throws {
        let suite = "dev.voxen.research-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var time = Date()
        let limiter = FreeTierLimiter(defaults: defaults, now: { time })
        let provider = OpenRouterProvider(apiKey: "fixture", model: OpenRouterProvider.defaultModel,
                                          client: makeClient(), limiter: limiter)
        var preferences = WritingPreferences()
        preferences.profile.enabled = true
        preferences.profile.work = "PRIVATE_PROFILE_FIXTURE"
        preferences.profile.samples = "PRIVATE_SAMPLE_FIXTURE"
        preferences.style.instructions = "PRIVATE_STYLE_FIXTURE"
        let context = VoiceContext(appName: "Chrome", bundleIdentifier: "private.bundle", mode: .social,
                                   selectedText: "PRIVATE_SELECTED_FIXTURE", transcript: "Write about the latest public launch.", writingPreferences: preferences)
        func response(_ content: String, annotations: [[String: Any]] = []) throws -> (Int, String) {
            let value: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": content, "annotations": annotations]]]]
            return (200, String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
        }
        var calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
            let messages = payload["messages"] as! [[String: String]]
            let input = messages[1]["content"]!
            if calls == 1 {
                check(payload["response_format"] != nil, "Research planner requests structured output")
                check(payload["plugins"] == nil && !input.contains("PRIVATE_SELECTED_FIXTURE") && !input.contains("private.bundle"), "Planner sees speech only and has no search")
                check(!input.contains("PRIVATE_PROFILE_FIXTURE") && !input.contains("PRIVATE_SAMPLE_FIXTURE") && !input.contains("PRIVATE_STYLE_FIXTURE"), "Profile, samples and style never reach planning")
                let planInput = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: Any]
                check(planInput["SELECTION_AVAILABLE"] as? Bool == true, "Planner knows a selection exists without receiving it")
                return try response(#"{"query":"public launch official announcement"}"#)
            }
            if calls == 2 {
                check(payload["plugins"] as? [[String: String]] == [["id": "web", "engine": "native"]], "Native Google search explicitly enabled")
                check(!input.contains("PRIVATE_SELECTED_FIXTURE") && !input.contains("Write about"), "Search gets only public query, not selection or original speech")
                check(!input.contains("PRIVATE_PROFILE_FIXTURE") && !input.contains("PRIVATE_SAMPLE_FIXTURE") && !input.contains("PRIVATE_STYLE_FIXTURE"), "Profile, samples and style never reach native search")
                return try response("Verified public briefing.", annotations: [
                    ["type": "url_citation", "url_citation": ["url": "https://official.example/launch"]],
                    ["type": "url_citation", "url_citation": ["url": "javascript:alert(1)"]]
                ])
            }
            check(payload["plugins"] == nil, "Final writing cannot perform additional searches")
            check(input.contains("PUBLIC_RESEARCH") && input.contains("Verified public briefing.") && input.contains("PRIVATE_SELECTED_FIXTURE"), "Writer combines original context and research")
            check(input.contains("PRIVATE_PROFILE_FIXTURE") && input.contains("PRIVATE_SAMPLE_FIXTURE") && input.contains("PRIVATE_STYLE_FIXTURE"), "Only final writer receives enabled saved writing context")
            return try response("A developed, grounded post.")
        }
        let generated = try await IntentTransformer(provider: provider).transform(context)
        check(calls == 3, "Researched requests use bounded planning, research, writing stages")
        check(generated.text.contains("https://official.example/launch") && !generated.text.contains("javascript:"), "Only safe provider citation URLs retained")
        calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
            check(payload["plugins"] == nil, "Non-research writing never enables search")
            return try response(calls == 1 ? #"{"query":null}"# : "Tuesday works.")
        }
        let ordinary = try await IntentTransformer(provider: provider).transform(context)
        check(calls == 2 && ordinary.text == "Tuesday works.", "Null research plan goes directly to writing")
        calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            if calls == 1 { return try response(#"{"query":"public topic"}"#) }
            if calls == 2 { return try response("Unsourced claim https://invented.example/fact") }
            let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
            let messages = payload["messages"] as! [[String: String]]
            let input = messages[1]["content"]!
            check(payload["plugins"] == nil, "No-source fallback never repeats search")
            check(input.contains("unavailable_sources") && !input.contains("PUBLIC_RESEARCH"), "Writer explicitly knows research is unavailable")
            check(!input.contains("Unsourced claim") && !input.contains("invented.example"), "Uncited briefing and invented links are discarded")
            check(input.contains("PRIVATE_SELECTED_FIXTURE"), "No-source fallback retains original selected context")
            return try response("I couldn't verify the current details. Please share a source.")
        }
        let unavailable = try await IntentTransformer(provider: provider).transform(context)
        check(calls == 3 && unavailable.text.contains("Please share a source"), "No citations still returns a completed LLM response")
        check(!unavailable.text.contains("Sources:") && !unavailable.text.contains("Unsourced claim"), "No fake source footer or briefing is copied")
        check(PromptTemplates.researchPlanner.contains("Default to") && PromptTemplates.researchPlanner.contains("name alone does NOT justify search"), "Planner policy makes research exceptional")
        calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return try response(#"{"query":"private@example.test"}"#) }
        do { _ = try await IntentTransformer(provider: provider).transform(context); fatalError("Expected private query rejection") }
        catch { check(calls == 1, "Email-like queries rejected before search") }
        for _ in 0..<18 { try limiter.reserveResearchRequest() }
        do { try limiter.reserveResearchRequest(); fatalError("Expected daily research cap") }
        catch { check(error.localizedDescription.contains("20"), "Daily research request cap enforced") }
        let restored = FreeTierLimiter(defaults: defaults, now: { time })
        do { try restored.reserveResearchRequest(); fatalError("Expected persisted cap") }
        catch { check(true, "Research cap survives restart") }
        time = time.addingTimeInterval(86_401)
        try restored.reserveResearchRequest()
        check(true, "Research allowance expires after 24 hours")
    }

    @MainActor static func testWritingPreferences() async throws {
        let suite = "dev.voxen.writing-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WritingPreferencesStore(defaults: defaults)
        check(!store.saved.profile.enabled, "Personal context is opt-in")
        check(store.saved.destinations.allSatisfy { !$0.enabled }, "Platform presets are inactive until enabled")
        var preferences = store.saved
        preferences.style.depth = .elaborate
        preferences.style.assumptions = .suggested
        preferences.style.targetWords = 250
        preferences.profile.name = "PRIVATE_WRITER"
        preferences.profile.samples = "PRIVATE_STYLE_SAMPLE"
        preferences.destinations[0].enabled = true
        preferences.destinations[0].customStyle = true
        preferences.destinations[0].style.tone = .quirky
        preferences.destinations[0].style.hashtags = .few
        var context = VoiceContext(appName: "Chrome", bundleIdentifier: "com.google.Chrome", mode: .generic,
                                   selectedText: nil, transcript: "Write a post", website: WebsiteContext(host: "www.x.com"))
        check(preferences.matchingDestination(context)?.id == "x", "Subdomain matches exact saved platform")
        check(preferences.payload(for: context)["tone"] as? String == WritingTone.quirky.rawValue, "Platform custom tone wins over global default")
        check(preferences.payload(for: context)["character_budget"] as? Int == 280, "Non-premium X has 280-character guidance")
        check(preferences.instructions(for: context).contains("280 characters") && preferences.instructions(for: context).contains("Quirky"), "Resolved platform budget and tone are explicit system instructions")
        preferences.destinations[0].longPosts = true
        check(preferences.payload(for: context)["character_budget"] as? Int == 25000, "Explicit longer-post setting updates X budget")
        context.website = WebsiteContext(host: "twitter.com")
        check(preferences.matchingDestination(context)?.id == "x", "X legacy hostname resolves")
        context.website = WebsiteContext(host: "notx.com")
        check(preferences.matchingDestination(context) == nil, "Hostname suffix lookalike cannot match")
        check(preferences.payload(for: context)["target_words"] as? Int == 250, "Unmatched site uses global word target")
        preferences.destinations.append(WritingDestination(name: "Mail", target: "https://www.mail.example/path?private=1", enabled: true))
        try store.save(preferences)
        check(store.saved.destinations.last?.target == "mail.example", "Only normalized hostname is persisted for destination matching")
        check(WritingPreferencesStore(defaults: defaults).saved == store.saved, "Writing preferences survive reload")
        var invalid = store.saved
        invalid.style.targetWords = -1
        do { try store.save(invalid); fatalError("Expected invalid length") }
        catch { check(store.saved.style.targetWords == 250, "Invalid save preserves prior preferences") }
        invalid = store.saved; invalid.profile.samples = String(repeating: "x", count: 6001)
        do { try store.save(invalid); fatalError("Expected profile length rejection") }
        catch { check(store.saved.profile.samples == "PRIVATE_STYLE_SAMPLE", "Oversized samples rejected without truncation or partial save") }
        invalid = store.saved; invalid.destinations.append(WritingDestination(name: "Duplicate", target: "www.x.com"))
        do { try store.save(invalid); fatalError("Expected duplicate rejection") }
        catch { check(true, "Duplicate normalized destinations rejected") }
        invalid = store.saved; invalid.destinations.append(WritingDestination(name: "Invalid", target: "javascript:alert(1)"))
        do { try store.save(invalid); fatalError("Expected invalid host") }
        catch { check(true, "Invalid website rejected") }
        invalid = store.saved; var duplicateID = WritingDestination(name: "Different", target: "different.example")
        duplicateID.id = invalid.destinations[0].id; invalid.destinations.append(duplicateID)
        do { try store.save(invalid); fatalError("Expected duplicate identifier rejection") }
        catch { check(true, "Duplicate destination identities cannot enter saved UI state") }
        preferences = store.saved
        preferences.destinations.append(WritingDestination(name: "Native editor", kind: .app, target: "com.example.editor", enabled: true))
        preferences.destinations[4].enabled = true
        context.website = nil; context = VoiceContext(appName: "Editor", bundleIdentifier: "com.example.editor", mode: .coding,
                                                     selectedText: nil, transcript: "Plan a feature")
        check(preferences.matchingDestination(context)?.name == "Native editor", "Native app preset wins over mode preset")
        preferences.destinations.removeLast()
        check(preferences.matchingDestination(context)?.id == "coding", "Mode preset works without website")
        context.writingPreferences = preferences
        let disabledProfileProvider = FixtureProvider { instructions, input in
            check(input.contains("WRITING_PREFERENCES") && input.contains("Suggest options"), "Resolved writing settings reach transformer payload")
            check(!input.contains("PRIVATE_WRITER") && !input.contains("PRIVATE_STYLE_SAMPLE") && !input.contains("WRITER_PROFILE"), "Disabled personal profile is not sent")
            check(instructions.contains("OPTIONAL proposals") && instructions.contains("untrusted style examples"), "Prompt separates proposed features and untrusted style samples from facts")
            check(instructions.contains("SUGGEST OPTIONS") && instructions.contains("250 words"), "Saved assumption policy and word target are active system instructions")
            check(!instructions.contains("PRIVATE_WRITER") && !instructions.contains("PRIVATE_STYLE_SAMPLE"), "User profile strings are data, never interpolated into system instructions")
            return "Suggested stack: follow the existing project conventions."
        }
        _ = try await IntentTransformer(provider: disabledProfileProvider).transform(context)
        preferences.profile.enabled = true
        context.writingPreferences = preferences
        let enabledProfileProvider = FixtureProvider { _, input in
            check(input.contains("PRIVATE_WRITER") && input.contains("PRIVATE_STYLE_SAMPLE"), "Enabled profile and samples reach final writing")
            check(!input.contains("mail.example"), "Unmatched saved platforms are not sent to the writer")
            return "A tailored response."
        }
        _ = try await IntentTransformer(provider: enabledProfileProvider).transform(context)
        preferences.profile = WriterProfile(); try store.save(preferences)
        let stored = String(decoding: defaults.data(forKey: WritingPreferencesStore.key)!, as: UTF8.self)
        check(!stored.contains("PRIVATE_WRITER") && !stored.contains("PRIVATE_STYLE_SAMPLE"), "Clearing profile removes saved personal fields")
        defaults.set(Data("broken".utf8), forKey: WritingPreferencesStore.key)
        check(WritingPreferencesStore(defaults: defaults).saved == WritingPreferences(), "Corrupt stored writing preferences safely fall back")
    }

    @MainActor static func testModelChoices() async throws {
        let suite = "dev.voxen.models-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, readSecret: { _ in "fixture-key" }, saveSecret: { _, _ in })
        let limiter = FreeTierLimiter(defaults: defaults)
        check(OpenRouterProvider.models.count == 5, "Five writing models available")
        check(Set(OpenRouterProvider.models.map(\.id)).count == OpenRouterProvider.models.count, "Model choices have unique IDs")
        for choice in OpenRouterProvider.models {
            var draft = settings.saved
            draft.model = choice.id
            try settings.save(draft)
            check(settings.model == choice.id && settings.isConfigured, "Selected model saves and remains configured")
            check(AppSettings(defaults: defaults, readSecret: { _ in "fixture-key" }, saveSecret: { _, _ in }).model == choice.id, "Model choice survives restart")
            var calls = 0
            MockURLProtocol.handler = { request in
                calls += 1
                let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
                let routing = payload["provider"] as! [String: Any]
                check(routing["data_collection"] as? String == "deny", "Privacy routing remains enabled for every model")
                if calls == 1 {
                    check(payload["model"] as? String == OpenRouterProvider.defaultModel && payload["plugins"] == nil, "Planning stays on Gemini without search")
                    check(payload["response_format"] != nil, "Planner keeps structured output")
                    return (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"query\":\"official public topic\"}"}}]}"#)
                }
                if calls == 2 {
                    check(payload["model"] as? String == OpenRouterProvider.defaultModel, "Research stays on the supported Gemini helper")
                    check(payload["plugins"] as? [[String: String]] == [["id":"web", "engine":"native"]], "Native search is not sent to alternate writing models")
                    check(routing["max_price"] as? [String: Double] == ["prompt":0.3, "completion":1.6, "request":0], "Research uses its own price ceilings")
                    return (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"A sourced briefing.","annotations":[{"type":"url_citation","url_citation":{"url":"https://official.example/topic"}}]}}]}"#)
                }
                check(payload["model"] as? String == choice.id, "Final writer uses the user's selected model")
                check(payload["plugins"] == nil && payload["response_format"] == nil, "Final writer gets neither search nor planner schema")
                check(routing["max_price"] as? [String: Double] == ["prompt":choice.inputCeiling, "completion":choice.outputCeiling, "request":0], "Each model uses compatible token ceilings")
                let reasoning = payload["reasoning"] as? [String: Any]
                if choice.requiresReasoning {
                    check(reasoning?["effort"] as? String == "minimal" && reasoning?["enabled"] == nil, "Mandatory reasoning is minimized, not disabled")
                } else { check(reasoning?["enabled"] as? Bool == false, "Optional reasoning remains disabled") }
                let messages = payload["messages"] as! [[String: String]]
                check(messages[1]["content"]!.contains("PUBLIC_RESEARCH"), "Selected writer receives source briefing")
                return (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"A model-specific finished response."}}]}"#)
            }
            let provider = OpenRouterProvider(apiKey: "fixture", model: choice.id, client: makeClient(), limiter: limiter)
            let generated = try await IntentTransformer(provider: provider).transform(VoiceContext(
                appName: "Browser", bundleIdentifier: nil, mode: .social, selectedText: nil, transcript: "Research a public topic"))
            check(calls == 3 && generated.text.contains("https://official.example/topic"), "Selected writing model retains citations from Gemini research")
        }
        defaults.set("unknown/model", forKey: "generationModel")
        check(AppSettings(defaults: defaults, readSecret: { _ in "" }, saveSecret: { _, _ in }).model == OpenRouterProvider.defaultModel, "Unavailable saved model falls back to default")
    }

    static func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(session: URLSession(configuration: config))
    }

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }

    static func main() async throws {
        let modes: [(String, String, ContextMode)] = [
            ("com.todesktop.230313mzl4w4u92", "Cursor", .coding),
            ("com.tinyspeck.slackmacgap", "Slack", .messaging),
            ("com.apple.Terminal", "Terminal", .terminal),
            ("com.apple.Notes", "Notes", .document),
            ("com.apple.Safari", "Safari", .generic),
            ("unknown", "Windsurf", .coding)
        ]
        for (id, name, expected) in modes {
            check(ApplicationDetector.resolve(bundleIdentifier: id, name: name) == expected, "Resolve \(name)")
        }
        check(PromptTemplates.instructions(for: .generic, hasSelection: true).contains("Apply the spoken instruction"), "Selected generic text gets transformation")
        check(PromptTemplates.instructions(for: .coding, hasSelection: true).contains("explain it instead"), "Explicit explanation overrides coding prompt")
        try await testWebsiteIntent()
        testSelectionCapture()
        testBrowserSurface()
        try await testResponseHistory()
        try await testGeminiResearch()
        try await testWritingPreferences()
        try await testModelChoices()

        let wav = AudioLevelMonitor.encodeWAV(pcm: Data([0, 0, 255, 127]), sampleRate: 16000)
        check(wav.count == 48, "WAV length")
        check(String(data: wav.prefix(4), encoding: .utf8) == "RIFF", "WAV signature")
        check(Array(wav[24..<28]) == [128, 62, 0, 0], "WAV sample rate")
        check(Array(wav.suffix(4)) == [0, 0, 255, 127], "WAV PCM bytes")

        var requests: [String] = []
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            requests.append("\(request.httpMethod!) \(path)")
            check(request.value(forHTTPHeaderField: "Authorization") == "test-key", "AssemblyAI authorization")
            switch (request.httpMethod!, path) {
            case ("POST", "/v2/upload"):
                check(body(of: request) == wav, "Uploaded WAV payload")
                check(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream", "Binary upload content type")
                return (200, #"{"upload_url":"https://cdn.assemblyai.com/test.wav"}"#)
            case ("POST", "/v2/transcript"):
                let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
                check(payload["speech_models"] as? [String] == ["universal-3-pro", "universal-2"], "AssemblyAI speech models")
                check(payload["audio_url"] as? String == "https://cdn.assemblyai.com/test.wav", "Submit uploaded URL")
                return (200, #"{"id":"test","status":"queued"}"#)
            case ("GET", "/v2/transcript/test"): return (200, #"{"id":"test","status":"completed","text":"Hello world."}"#)
            case ("DELETE", "/v2/transcript/test"): return (200, "{}")
            default: fatalError("Unexpected request \(path)")
            }
        }
        let service = AssemblyAIService(apiKey: "test-key", client: makeClient(), pollInterval: .milliseconds(1))
        let transcript = try await service.transcribe(audio: wav)
        check(transcript == "Hello world.", "AssemblyAI transcript decoded")
        check(requests == ["POST /v2/upload", "POST /v2/transcript", "GET /v2/transcript/test", "DELETE /v2/transcript/test"], "Upload, submit, poll, delete ordering")

        MockURLProtocol.handler = { _ in (401, #"{"error":"private input must not leak"}"#) }
        do {
            _ = try await service.transcribe(audio: wav)
            fatalError("Expected authentication error")
        } catch {
            check(error.localizedDescription.contains("401"), "Authentication error actionable")
            check(!error.localizedDescription.contains("private input"), "Provider body not exposed")
        }
        let suite = "dev.voiceintent.router.tests.provider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var requestTime = Date()
        let limiter = FreeTierLimiter(defaults: defaults, now: { requestTime })
        MockURLProtocol.handler = { request in
            check(request.url!.absoluteString == "https://openrouter.ai/api/v1/chat/completions", "OpenRouter chat endpoint")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "OpenRouter authorization")
            let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
            check(payload["model"] as? String == OpenRouterProvider.freeModel, "Free model selected")
            let routing = payload["provider"] as! [String: Any]
            check(routing["max_price"] as? [String: Int] == ["prompt": 0, "completion": 0, "request": 0], "No paid routing allowed")
            check(routing["data_collection"] as? String == "deny", "Data-collecting providers excluded")
            check(payload["stream"] as? Bool == false, "Non-streaming response")
            let messages = payload["messages"] as! [[String: String]]
            check(messages.map { $0["role"]! } == ["system", "user"], "System instructions separated from context")
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: String]
            check(input["CURRENT_SELECTED_CONTEXT"] == "Can we ship today?", "Selection included")
            check(input["CONTEXT_MODE"] == "messaging", "Mode included")
            check(input["SPOKEN_INTENT"] == "Tell him tomorrow morning is more realistic.", "Spoken intent included")
            return (200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Tomorrow morning is more realistic.","reasoning":"private reasoning"}}]}"#)
        }
        let provider = OpenRouterProvider(apiKey: "test-key", model: OpenRouterProvider.freeModel, client: makeClient(), limiter: limiter)
        let output = try await IntentTransformer(provider: provider).transform(VoiceContext(
            appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", mode: .messaging,
            selectedText: "Can we ship today?", transcript: "Tell him tomorrow morning is more realistic."))
        check(output.text == "Tomorrow morning is more realistic.", "Transform returns content, not reasoning")
        requestTime = requestTime.addingTimeInterval(4)
        MockURLProtocol.handler = { _ in (200, #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#) }
        do {
            _ = try await provider.generate(instructions: "test", input: "test")
            fatalError("Expected incomplete output rejection")
        } catch { check(error.localizedDescription.contains("did not finish"), "Never paste truncated output") }

        requestTime = requestTime.addingTimeInterval(4)
        var calls = 0
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]
        MockURLProtocol.handler = { _ in calls += 1; return (429, #"{"error":{"message":"private content"}}"#) }
        do {
            _ = try await provider.generate(instructions: "test", input: "test")
            fatalError("Expected rate limit")
        } catch {
            check(error.localizedDescription.contains("paused"), "429 reports cooldown")
            check(!error.localizedDescription.contains("private content"), "429 never exposes response body")
        }
        do {
            _ = try await provider.generate(instructions: "test", input: "test")
            fatalError("Expected local cooldown")
        } catch { check(calls == 1, "No automatic retries or requests during cooldown") }
        check(limiter.usageSummary.hasPrefix("3 / 50"), "Failed attempts count against allowance")
        let restoredLimiter = FreeTierLimiter(defaults: defaults, now: { requestTime })
        do { try restoredLimiter.checkAvailability(); fatalError("Cooldown lost on restart") }
        catch { check(error.localizedDescription.contains("paused"), "Cooldown survives limiter recreation") }
        requestTime = requestTime.addingTimeInterval(130)
        try restoredLimiter.checkAvailability()
        check(true, "Server cooldown eventually expires")
        MockURLProtocol.responseHeaders = [:]

        let paid = OpenRouterProvider(apiKey: "test-key", model: "meta-llama/llama-3.3-70b-instruct", client: makeClient(), limiter: limiter)
        do {
            _ = try await paid.generate(instructions: "test", input: "test")
            fatalError("Paid models must be blocked")
        } catch { check(calls == 1, "Paid model rejected before any network request") }
        check(OpenRouterProvider.isFreeModel("openrouter/free"), "Free router allowed")
        check(!OpenRouterProvider.isFreeModel("openrouter/auto"), "Paid auto router disallowed")
        try testFreeLimits()

        for _ in 3..<50 {
            requestTime = requestTime.addingTimeInterval(4)
            try limiter.reserveRequest()
        }
        MockURLProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: body(of: request)) as! [String: Any]
            check(payload["model"] as? String == "google/gemini-3.1-flash-lite", "Gemini Flash-Lite selected")
            let routing = payload["provider"] as! [String: Any]
            check(routing["max_price"] as? [String: Double] == ["prompt": 0.30, "completion": 1.60, "request": 0], "Gemini routing has token price ceilings")
            check(payload["max_tokens"] as? Int == 4000, "Writing has room for developed output")
            check(payload["plugins"] == nil, "Ordinary generation does not enable search")
            check(payload["temperature"] as? Double == 0.3, "Low temperature for restrained transformations")
            check(payload["reasoning"] as? [String: Bool] == ["enabled": false], "Reasoning disabled for simple text transformation")
            return (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"Refactor this implementation without changing its behavior."}}]}"#)
        }
        let qwen = OpenRouterProvider(apiKey: "test-key", model: OpenRouterProvider.defaultModel, client: makeClient(), limiter: limiter)
        let instruction = try await qwen.generate(instructions: "test", input: "test")
        check(instruction.hasPrefix("Refactor"), "Paid model works when free allowance is exhausted")
        check(limiter.usageSummary.hasPrefix("50 / 50"), "Paid request does not consume free allowance")
        var paidCalls = 0
        MockURLProtocol.responseHeaders = ["Retry-After": "120"]
        MockURLProtocol.handler = { _ in paidCalls += 1; return (429, "{}") }
        do { _ = try await qwen.generate(instructions: "test", input: "test"); fatalError("Expected paid 429") }
        catch { check(error.localizedDescription.contains("paused"), "Paid requests respect server cooldown") }
        do { _ = try await qwen.generate(instructions: "test", input: "test"); fatalError("Expected paid cooldown") }
        catch { check(paidCalls == 1, "Paid request does not retry during cooldown") }
        MockURLProtocol.responseHeaders = [:]
        check(PromptTemplates.instructions(for: .coding, hasSelection: true).contains("imperative instructions"), "Coding requests do not become completion reports")
        try testSettings()
        if ProcessInfo.processInfo.environment["VOXEN_SKIP_HOTKEY_TEST"] != "1" {
            try testShortcutRegistration()
        }

        var deleted = false
        MockURLProtocol.handler = { request in
            if request.httpMethod == "DELETE" { deleted = true; return (200, "{}") }
            if request.url!.path.hasSuffix("upload") { return (200, #"{"upload_url":"https://cdn.assemblyai.com/test.wav"}"#) }
            return (200, #"{"id":"silent","status":"completed","text":"   "}"#)
        }
        do {
            _ = try await service.transcribe(audio: wav)
            fatalError("Expected no-speech failure")
        } catch { check(error.localizedDescription.contains("No speech"), "Empty transcript rejected") }
        check(deleted, "Empty transcript cleaned up remotely")

        deleted = false
        MockURLProtocol.handler = { request in
            if request.httpMethod == "DELETE" { deleted = true; return (200, "{}") }
            if request.url!.path.hasSuffix("upload") { return (200, #"{"upload_url":"https://cdn.assemblyai.com/test.wav"}"#) }
            return (200, #"{"id":"slow","status":"processing"}"#)
        }
        let timeoutService = AssemblyAIService(apiKey: "test-key", client: makeClient(), pollInterval: .milliseconds(1), timeout: .milliseconds(3))
        do {
            _ = try await timeoutService.transcribe(audio: wav)
            fatalError("Expected timeout")
        } catch { check(error.localizedDescription.contains("timed out"), "Polling bounded by deadline") }
        check(deleted, "Timed-out job cleanup attempted")

        let cleaned = ClipboardOutput.clean("\n────────────────────\n\n  Refactor this code.\n")
        check(cleaned == "Refactor this code.", "Decorative rulers and surrounding whitespace removed")
        check(ClipboardOutput.clean("\u{001b}[31mHello\u{001b}[0m") == "Hello", "ANSI formatting removed completely")
        check(ClipboardOutput.clean("First\r\nSecond\n") == "First\nSecond", "Clipboard output preserves paragraphs")
        try await testClipboard()
        print("PASS: \(checks) checks (offline fixtures; no live API or microphone calls)")
    }

    @MainActor
    static func testWebsiteIntent() async throws {
        let fixtures: [(String, String)] = [
            ("https://x.com/compose/post", "x.com"),
            ("https://www.linkedin.com/feed/", "www.linkedin.com"),
            ("https://www.instagram.com/direct/", "www.instagram.com"),
            ("https://mail.google.com/mail/u/0/", "mail.google.com"),
            ("https://outlook.office.com/mail/", "outlook.office.com"),
            ("https://new-community.example/topic/42", "new-community.example"),
            ("https://x.com.evil.example/", "x.com.evil.example"),
            ("https://example.com/x.com", "example.com")
        ]
        for (url, host) in fixtures {
            let site = WebsiteContext.from(urlString: url)
            check(site?.host == host, "Exact hostname retained without site mapping: \(url)")
            check(ApplicationDetector.resolve(bundleIdentifier: "com.google.Chrome", name: "Chrome", website: site) == .generic,
                  "Website is left for model interpretation: \(url)")
        }
        for invalid in ["file:///private/x.com", "javascript:alert(1)", "chrome://settings", "not a URL", "x.com"] {
            check(WebsiteContext.from(urlString: invalid) == nil, "Non-web URL rejected: \(invalid)")
        }
        let x = WebsiteContext.from(urlString: "https://X.COM./compose/post?private=secret#private")!
        check(x.host == "x.com", "Only normalized hostname retained")
        check(ApplicationDetector.resolve(bundleIdentifier: "com.apple.Safari", name: "Safari", website: x, override: .document) == .document,
              "Manual override wins over website detection")
        check(ApplicationDetector.resolve(bundleIdentifier: "com.apple.Notes", name: "Notes", website: x) == .document,
              "Website routing applies only to browsers")
        check(ApplicationDetector.resolve(bundleIdentifier: "com.apple.Safari", name: "Safari", website: nil) == .generic,
              "Unavailable browser context gracefully uses generic mode")
        let generic = PromptTemplates.instructions(for: .generic, hasSelection: false)
        check(generic.contains("NOT mandatory dictation"), "Generic requests infer intent instead of forcing dictation")
        check(generic.lowercased().contains("missing context"), "No unseen page or selection invented")
        check(!generic.contains("LinkedIn") && !generic.contains("Instagram") && !generic.contains("Gmail"), "System policy contains no platform-specific rules")
        check(generic.contains("reply") && generic.contains("caption") && generic.contains("email"), "General writing forms are defined")
        check(generic.contains("not merely the transcript"), "Social writing requires refinement")
        check(PromptTemplates.instructions(for: .social, hasSelection: true, modeIsOverride: true).contains("selected this mode manually"), "Manual modes distinguished from automatic hints")

        struct InspectingProvider: LLMProvider {
            let inspect: (String, String) throws -> String
            func generate(instructions: String, input: String) async throws -> String { try inspect(instructions, input) }
        }
        let provider = InspectingProvider { instructions, input in
            let json = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: String]
            check(json["WEBSITE_HOST"] == "x.com", "Host reaches the transformer")
            check(json["PLATFORM"] == nil, "No hardcoded platform label sent")
            check(json["APPLICATION"] == "Chrome", "Actual browser retained separately")
            check(json["CONTEXT_MODE"] == "generic", "Generic browser hint leaves model free to infer social context")
            check(json["MODE_SOURCE"] == "application_hint", "Automatic hint is not presented as an override")
            check(json["SELECTION_STATUS"] == "unavailable", "Missing selection is explicit")
            check(json["SPOKEN_INTENT"] == "Write a short post saying benchmarks do not reflect real coding work.", "Intent retained")
            check(json["CURRENT_SELECTED_CONTEXT"] == "", "Missing selection stays absent")
            check(!input.contains("secret") && !input.contains("compose"), "URL path, query and fragment never sent")
            check(instructions.contains("Fulfil the requested action"), "Output instruction is action-oriented")
            return "Benchmarks don't tell us how useful a coding model is on real work."
        }
        let output = try await IntentTransformer(provider: provider).transform(VoiceContext(
            appName: "Chrome", bundleIdentifier: "com.google.Chrome", mode: .generic,
            selectedText: nil, transcript: "Write a short post saying benchmarks do not reflect real coding work.", website: x))
        check(output.text.hasPrefix("Benchmarks"), "Website-aware pipeline returns generated content")
        let selectionProvider = FixtureProvider { instructions, input in
            let json = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: String]
            check(json["CURRENT_SELECTED_CONTEXT"] == "Could you send the draft today?", "Selected source preserved independently of voice intent")
            check(json["SELECTION_STATUS"] == "included", "Selection availability provided")
            check(json["WEBSITE_HOST"] == "unknown-mail.example", "Previously unknown site reaches the LLM")
            check(instructions.contains("Highlighting someone else's text does not mean rewriting it"), "Selection role inferred from spoken intent")
            return "Tomorrow morning works better."
        }
        _ = try await IntentTransformer(provider: selectionProvider).transform(VoiceContext(
            appName: "Browser", bundleIdentifier: nil, mode: .generic,
            selectedText: "Could you send the draft today?", transcript: "Reply saying tomorrow morning works better",
            website: WebsiteContext.from(urlString: "https://unknown-mail.example/thread")))
    }

    static func testSelectionCapture() {
        let field = AXUIElementCreateApplication(123)
        let parent = AXUIElementCreateApplication(124)
        let text = "  Could you send the draft today?"
        let direct = SelectedTextReader(attribute: { _, name in
            name == kAXSelectedTextAttribute ? text as CFString : nil
        }, stringForRange: { _, _ in fatalError("Direct selection should avoid range fallback") })
        check(direct.read(focused: field) == text, "Direct selected text preserves formatting")
        let ancestor = SelectedTextReader(attribute: { element, name in
            if name == kAXParentAttribute && CFEqual(element, field) { return parent }
            if name == kAXSelectedTextAttribute && CFEqual(element, parent) { return text as CFString }
            return nil
        }, stringForRange: { _, _ in nil })
        check(ancestor.read(focused: field) == text, "Enclosing web area can provide highlighted text")
        var range = CFRange(location: 4, length: 7)
        let rangeValue = AXValueCreate(.cfRange, &range)!
        let ranged = SelectedTextReader(attribute: { _, name in
            name == kAXSelectedTextRangeAttribute ? rangeValue : nil
        }, stringForRange: { _, range in
            check(range.location == 4 && range.length == 7, "Only selected substring requested")
            return "example"
        })
        check(ranged.read(focused: field) == "example", "Selection range fallback works")
        let marker = "opaque text marker range" as CFString
        let marked = SelectedTextReader(attribute: { _, name in
            name == "AXSelectedTextMarkerRange" ? marker : nil
        }, stringForRange: { _, _ in nil }, stringForMarkerRange: { _, supplied in
            check(CFEqual(supplied, marker), "Browser's opaque selected marker range passed through unchanged")
            return "First paragraph.\nSecond paragraph."
        })
        check(marked.read(focused: field) == "First paragraph.\nSecond paragraph.", "Cross-element web selections supported via markers")
        let secure = SelectedTextReader(attribute: { _, name in
            if name == kAXSubroleAttribute { return "AXSecureTextField" as CFString }
            fatalError("Secure field must not be read")
        }, stringForRange: { _, _ in fatalError("Secure field range must not be read") })
        check(secure.read(focused: field) == nil, "Secure fields skip all selection reads")
        var calls = 0
        var selectionAttributes = Set<String>()
        let cyclic = SelectedTextReader(attribute: { _, name in
            calls += 1
            selectionAttributes.insert(name)
            return name == kAXParentAttribute ? field : nil
        }, stringForRange: { _, _ in nil })
        check(cyclic.read(focused: field) == nil && calls <= 96, "Broken ancestor cycles are bounded")
        check(!selectionAttributes.contains(kAXValueAttribute) && !selectionAttributes.contains(kAXChildrenAttribute), "Never read full values or page children")
        check(SelectedTextReader.usableSelection(" \n ") == nil, "Blank selection becomes unavailable")
        check(SelectedTextReader.usableSelection(String(repeating: "a", count: 13_000))?.count == 12_000, "Selected source size bounded")
        check(SelectedTextReader.boundedRange(CFRange(location: -1, length: 5)) == nil, "Negative selection range rejected")
        check(SelectedTextReader.boundedRange(CFRange(location: 0, length: 0)) == nil, "Caret is not a selection")
        check(SelectedTextReader.boundedRange(CFRange(location: Int.max, length: 1)) == nil, "Overflowing selection rejected")
        check(SelectedTextReader.boundedRange(CFRange(location: 1, length: 20_000))?.length == 12_000, "Range read is capped")
    }

    static func testBrowserSurface() {
        let app = AXUIElementCreateApplication(201)
        let window = AXUIElementCreateApplication(202)
        let group = AXUIElementCreateApplication(203)
        let page = AXUIElementCreateApplication(204)
        let otherPage = AXUIElementCreateApplication(205)
        var multiplePages = false
        var hideOtherPage = false
        let browser = BrowserContextReader(attribute: { element, name in
            if name == kAXFocusedUIElementAttribute && CFEqual(element, app) { return window }
            if name == "AXHidden" && CFEqual(element, otherPage) { return hideOtherPage ? kCFBooleanTrue : kCFBooleanFalse }
            if name == kAXRoleAttribute {
                return (CFEqual(element, window) ? "AXWindow" : CFEqual(element, group) ? "AXGroup" : "AXWebArea") as CFString
            }
            if name == kAXChildrenAttribute {
                if CFEqual(element, window) { return [group] as CFArray }
                if CFEqual(element, group) { return (multiplePages ? [page, otherPage] : [page]) as CFArray }
                fatalError("Must not traverse page content")
            }
            if name == kAXURLAttribute && CFEqual(element, page) { return "https://arbitrary-site.example/private?token=secret" as CFString }
            return nil
        })
        let found = browser.surface(app: app, window: window)
        check(found.website?.host == "arbitrary-site.example", "Web area found when highlighted document does not own keyboard focus")
        check(found.webArea.map { CFEqual($0, page) } == true, "Surface retains active web area for selected marker reads")
        multiplePages = true
        check(browser.surface(app: app, window: window).webArea == nil, "Ambiguous multiple web areas are not guessed")
        hideOtherPage = true
        check(browser.surface(app: app, window: window).website?.host == "arbitrary-site.example", "Hidden page surfaces ignored")
    }

    @MainActor
    static func testFreeLimits() throws {
        let suite = "dev.voiceintent.router.tests.quota.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var now = start
        let limiter = FreeTierLimiter(defaults: defaults, now: { now })
        try limiter.reserveRequest()
        now = start.addingTimeInterval(3)
        do { try limiter.reserveRequest(); fatalError("Requests too close together") }
        catch { check(error.localizedDescription.contains("paused"), "Per-minute spacing enforced") }
        for index in 1..<50 {
            now = start.addingTimeInterval(Double(index) * 3.2)
            try limiter.reserveRequest()
        }
        now = now.addingTimeInterval(4)
        do { try limiter.reserveRequest(); fatalError("Daily quota exceeded") }
        catch { check(error.localizedDescription.contains("paused"), "51st attempt blocked") }
        let restored = FreeTierLimiter(defaults: defaults, now: { now })
        check(restored.usageSummary.hasPrefix("50 / 50"), "Usage survives limiter recreation")
        now = start.addingTimeInterval(86_400)
        try restored.reserveRequest()
        check(restored.usageSummary.hasPrefix("50 / 50"), "Rolling limit releases only the expired attempt")

        func response(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
        }
        let seconds = APIHTTPError(service: "OpenRouter", response: response(["Retry-After": "120"]), now: start)
        check(seconds.retryAt == start.addingTimeInterval(120), "Retry-After seconds parsed")
        let httpDate = APIHTTPError(service: "OpenRouter", response: response(["Retry-After": "Tue, 14 Nov 2023 22:15:20 GMT"]), now: start)
        check(httpDate.retryAt == start.addingTimeInterval(120), "Retry-After HTTP date parsed")
        let reset = APIHTTPError(service: "OpenRouter", response: response(["Retry-After": "30", "X-RateLimit-Reset": "1700000180000"]), now: start)
        check(reset.retryAt == start.addingTimeInterval(180), "Later millisecond reset takes precedence")
        let resetSeconds = APIHTTPError(service: "OpenRouter", response: response(["X-RateLimit-Reset": "1700000180"]), now: start)
        check(resetSeconds.retryAt == start.addingTimeInterval(180), "Second reset timestamp supported")
        let invalid = APIHTTPError(service: "OpenRouter", response: response(["Retry-After": "NaN", "X-RateLimit-Reset": "invalid"]), now: start)
        check(invalid.retryAt == nil, "Malformed cooldown headers ignored")
        _ = limiter.recordRateLimit(retryAt: nil)
        now = now.addingTimeInterval(59)
        do { try limiter.checkAvailability(); fatalError("Default cooldown missing") }
        catch { check(error.localizedDescription.contains("paused"), "Missing headers use a 60-second cooldown") }
    }

    @MainActor
    static func testClipboard() async throws {
        let output = MemoryClipboard("original")
        let context = VoiceContext(appName: "Browser", bundleIdentifier: nil, mode: .generic,
                                   selectedText: "Could you send the draft today?", transcript: "RAW SPEECH INPUT")
        let transformer = IntentTransformer(provider: FixtureProvider { _, _ in "  generated  " })
        try await transformer.transformAndCopy(context, to: output)
        check(output.string == "generated", "Generated clipboard value")
        try await Task.sleep(for: .milliseconds(2200))
        check(output.string == "generated", "Generated text remains after the old restoration deadline")
        output.string = "new user copy"
        check(output.string == "new user copy", "User can replace generated clipboard content")
        for response in ["────────────", "", "  \n "] {
            let empty = IntentTransformer(provider: FixtureProvider { _, _ in response })
            do { try await empty.transformAndCopy(context, to: output); fatalError("Empty model output must fail") }
            catch { check(output.string == "new user copy", "Empty output never falls back to STT") }
        }
        for failure in [RouterError.message("Offline") as Error, CancellationError() as Error] {
            let failed = IntentTransformer(provider: FixtureProvider { _, _ in throw failure })
            do { try await failed.transformAndCopy(context, to: output); fatalError("Provider failure must propagate") }
            catch { check(output.string == "new user copy", "Failure/cancellation never copies raw speech") }
        }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await transformer.transformAndCopy(context, to: output)
        }
        do { try await cancelled.value; fatalError("Cancelled task must not copy") }
        catch { check(output.string == "new user copy", "Cancelled request leaves clipboard untouched") }
    }

    @MainActor
    static func testSettings() throws {
        let suite = "dev.voiceintent.router.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var secrets: [String: String] = [:]
        var failWrites = false
        defaults.set(OpenRouterProvider.freeModel, forKey: "generationModel")
        let settings = AppSettings(defaults: defaults, readSecret: { _ in "" }, saveSecret: { value, account in
            if failWrites { throw RouterError.message("Test write failure") }
            secrets[account] = value
        })
        var draft = settings.saved
        check(settings.model == OpenRouterProvider.defaultModel, "Older model preference resolves to Gemini")
        var unsupported = draft
        unsupported.model = OpenRouterProvider.freeModel
        do { try settings.save(unsupported); fatalError("Expected catalog validation") }
        catch { check(settings.saved == draft, "Models outside the curated picker cannot be saved") }
        check(draft.normalized == settings.saved, "Unchanged settings disable Save")
        draft.assemblyAIKey = " test-assembly "
        draft.openRouterKey = "test-router"
        draft.shortcut = VoiceShortcut(keyCode: 40, modifiers: VoiceShortcut.modifierChoices[1].value)
        check(draft.normalized != settings.saved, "Editing settings enables Save")
        var active = VoiceShortcut.standard
        settings.applyShortcut = { active = $0 }
        try settings.save(draft)
        draft = settings.saved
        check(draft.normalized == settings.saved, "Successful save clears dirty state")
        check(settings.isConfigured, "Gemini configuration accepted")
        check(secrets["assemblyai"] == "test-assembly", "Secrets normalized before saving")
        check(active == draft.shortcut, "New shortcut applied on Save")
        let reloaded = AppSettings(defaults: defaults, readSecret: { secrets[$0] ?? "" }, saveSecret: { _, _ in })
        check(reloaded.saved == settings.saved, "Keys, model and shortcut reload correctly")
        let previous = settings.saved
        draft.openRouterKey = "changed"
        draft.shortcut = .standard
        failWrites = true
        do { try settings.save(draft); fatalError("Expected failed save") }
        catch {
            check(settings.saved == previous, "Failed save never reports success")
            check(draft.normalized != settings.saved, "Failed save remains editable")
            check(active == previous.shortcut, "Keychain failure restores the previous shortcut")
        }
        failWrites = false
        settings.applyShortcut = { _ in throw HotkeyError.registration(-1) }
        do { try settings.save(draft); fatalError("Expected shortcut conflict") }
        catch { check(settings.saved == previous, "Shortcut conflict keeps saved settings unchanged") }
        check(!VoiceShortcut(keyCode: 49, modifiers: 0).isValid, "Unmodified shortcuts disallowed")
    }

    @MainActor
    static func testShortcutRegistration() throws {
        let modifiers = VoiceShortcut.modifierChoices[1].value
        let first = GlobalHotkeyManager()
        var blocker: GlobalHotkeyManager? = GlobalHotkeyManager()
        // Use uncommon test bindings; do not fire any key events.
        let old = VoiceShortcut(keyCode: 6, modifiers: modifiers)
        let next = VoiceShortcut(keyCode: 7, modifiers: modifiers)
        try first.register(old)
        try blocker!.register(next)
        do { try first.register(next); fatalError("Expected registered-key conflict") }
        catch { check(true, "Conflicting shortcut registration fails") }
        let probe = GlobalHotkeyManager()
        do { try probe.register(old); fatalError("Old shortcut unexpectedly released") }
        catch { check(true, "Conflict preserves old registration") }
        blocker = nil
        try first.register(next)
        try probe.register(old)
        check(true, "Successful rebind releases old shortcut")
    }
}
