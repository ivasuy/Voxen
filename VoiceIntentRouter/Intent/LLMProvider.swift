import Foundation

protocol LLMProvider {
    func generate(instructions: String, input: String) async throws -> String
}

struct OpenRouterModel: Identifiable {
    let id: String
    let name: String
    let inputCeiling: Double
    let outputCeiling: Double
    var requiresReasoning = false
    var priceSummary: String {
        "Token ceiling: $\(inputCeiling.formatted())/M input · $\(outputCeiling.formatted())/M output"
    }
}

struct OpenRouterProvider: LLMProvider {
    static let defaultModel = "google/gemini-3.1-flash-lite"
    static let modelLabel = "Gemini 3.1 Flash-Lite"
    static let freeModel = "meta-llama/llama-3.3-70b-instruct:free"
    // Explicit choices keep provider parameters and spending ceilings predictable.
    static let models: [OpenRouterModel] = [
        .init(id: defaultModel, name: modelLabel, inputCeiling: 0.30, outputCeiling: 1.60),
        .init(id: "qwen/qwen3.8-flash", name: "Qwen3.8 Flash", inputCeiling: 0.20, outputCeiling: 0.60),
        .init(id: "deepseek/deepseek-v4.1-flash", name: "DeepSeek V4.1 Flash", inputCeiling: 0.35, outputCeiling: 1.30),
        .init(id: "google/gemini-3.5-flash", name: "Gemini 3.5 Flash", inputCeiling: 1.60, outputCeiling: 9.50, requiresReasoning: true),
        .init(id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5", inputCeiling: 1.10, outputCeiling: 5.20)
    ]
    static func option(_ id: String) -> OpenRouterModel? { models.first { $0.id == id } }
    let apiKey: String
    let model: String
    var client = APIClient()
    let limiter: FreeTierLimiter

    static func isFreeModel(_ model: String) -> Bool {
        model == "openrouter/free" || (model.contains("/") && model.hasSuffix(":free") && !model.contains(where: \.isWhitespace))
    }
    static func isSupportedModel(_ model: String) -> Bool { option(model) != nil || isFreeModel(model) }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct Annotation: Decodable {
                    struct Citation: Decodable { let url: String; let title: String? }
                    let type: String
                    let url_citation: Citation?
                }
                let content: String?
                let annotations: [Annotation]?
            }
            let finish_reason: String?
            let message: Message
        }
        struct Failure: Decodable { let code: Int? }
        let choices: [Choice]?
        let error: Failure?
    }

    func generate(instructions: String, input: String) async throws -> String {
        var writingInput = input
        var sourceURLs: [String] = []
        // Planning sees speech and selection availability, never selected text, app metadata or history.
        if Self.option(model) != nil,
           var context = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any],
           let speech = context["SPOKEN_INTENT"] as? String {
            let date = ISO8601DateFormatter().string(from: Date())
            let selection = context["CURRENT_SELECTED_CONTEXT"] as? String
            let planningInput = try JSONSerialization.data(withJSONObject: [
                "SPOKEN_INTENT": speech, "CURRENT_DATE": date,
                "SELECTION_AVAILABLE": !(selection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ])
            let planResponse = try await complete(instructions: PromptTemplates.researchPlanner,
                input: String(decoding: planningInput, as: UTF8.self), maxTokens: 256, plan: true, using: Self.defaultModel)
            struct Plan: Decodable { let query: String? }
            guard let plan = try? JSONDecoder().decode(Plan.self, from: Data(try content(planResponse).utf8)) else {
                throw RouterError.message("Could not interpret the request. Try again with a clearer instruction.")
            }
            if let query = plan.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                guard query.count <= 300, !query.contains("@"), !query.contains("\n") else {
                    throw RouterError.message("Ask for a public topic without private details to use web search.")
                }
                try await limiter.reserveResearchRequest()
                let researchInput = try JSONSerialization.data(withJSONObject: ["PUBLIC_QUERY": query, "CURRENT_DATE": date])
                let research = try await complete(instructions: PromptTemplates.publicResearch,
                    input: String(decoding: researchInput, as: UTF8.self), maxTokens: 1800, search: true, using: Self.defaultModel)
                let summary = try content(research)
                for annotation in research.choices?.first?.message.annotations ?? [] {
                    guard annotation.type == "url_citation", let raw = annotation.url_citation?.url,
                          let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                          url.host != nil, !sourceURLs.contains(raw) else { continue }
                    sourceURLs.append(raw)
                }
                sourceURLs = Array(sourceURLs.prefix(8))
                if sourceURLs.isEmpty {
                    // Missing annotations are not a writing failure. Never pass the unsourced claims to the writer.
                    context["RESEARCH_STATUS"] = "unavailable_sources"
                } else {
                    context["PUBLIC_RESEARCH"] = ["summary": summary, "sources": sourceURLs]
                }
            }
            context["CURRENT_DATE"] = date
            writingInput = String(decoding: try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]), as: UTF8.self)
        }
        let result = try content(await complete(instructions: instructions, input: writingInput, maxTokens: 4000))
        // URLs come from provider annotations, not model transcription of opaque redirect links.
        guard !sourceURLs.isEmpty else { return result }
        let sources = sourceURLs.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        return result + "\n\nSources:\n" + sources
    }

    private func content(_ response: Response) throws -> String {
        guard let choice = response.choices?.first, choice.finish_reason == "stop" else {
            throw RouterError.message("The model did not finish its response. Try again or narrow the request.")
        }
        let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw RouterError.message("The model returned no text. Rephrase the request and try again.") }
        return text
    }

    private func complete(instructions: String, input: String, maxTokens: Int,
                          search: Bool = false, plan: Bool = false, using requestedModel: String? = nil) async throws -> Response {
        guard !apiKey.isEmpty else { throw RouterError.message("Add your OpenRouter API key in Settings.") }
        let activeModel = requestedModel ?? model
        guard Self.isSupportedModel(model), Self.isSupportedModel(activeModel) else {
            throw RouterError.message("This model is unavailable. Choose a model in Settings.")
        }
        let free = Self.isFreeModel(activeModel)
        let option = Self.option(activeModel)
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": activeModel,
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": input]],
            "max_tokens": maxTokens, "stream": false, "temperature": plan ? 0.0 : 0.3,
            "provider": ["max_price": ["prompt": option?.inputCeiling ?? 0.0, "completion": option?.outputCeiling ?? 0.0, "request": 0.0], "data_collection": "deny"]
        ]
        if !free {
            payload["reasoning"] = option?.requiresReasoning == true ? ["effort": "minimal"] : ["enabled": false]
        }
        if search { payload["plugins"] = [["id": "web", "engine": "native"]] }
        if plan {
            payload["response_format"] = ["type": "json_schema", "json_schema": [
                "name": "research_plan", "strict": true,
                "schema": ["type": "object", "properties": ["query": ["type": ["string", "null"]]],
                           "required": ["query"], "additionalProperties": false]
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        try Task.checkCancellation()
        // Failed requests still consume the local allowance. Never automatically retry.
        if free { try await limiter.reserveRequest() }
        else { try await limiter.checkPaidAvailability() }
        do {
            let data = try await client.send(request, service: "OpenRouter")
            let response = try JSONDecoder().decode(Response.self, from: data)
            if let error = response.error {
                if error.code == 429 { throw await limiter.recordRateLimit(retryAt: nil, free: free) }
                throw RouterError.message("OpenRouter could not generate text. Check model availability and try again later.")
            }
            return response
        } catch let error as APIHTTPError where error.statusCode == 429 {
            throw await limiter.recordRateLimit(retryAt: error.retryAt, free: free)
        }
    }
}

/// Conservative app-wide budget, shared across models and keys and retained across launches.
/// Persists only request timestamps, never speech, selections, keys, or output.
@MainActor
final class FreeTierLimiter {
    static let shared = FreeTierLimiter()
    static let dailyLimit = 50
    static let spacing: TimeInterval = 3.1
    private let defaults: UserDefaults
    private let now: () -> Date
    private let attemptsKey = "openrouter.free.attempts"
    private let cooldownKey = "openrouter.free.cooldownUntil"
    private let paidCooldownKey = "openrouter.paid.cooldownUntil"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    private var attempts: [TimeInterval] {
        let cutoff = now().timeIntervalSince1970 - 86_400
        return (defaults.array(forKey: attemptsKey) as? [Double] ?? []).filter { $0 > cutoff }.sorted()
    }

    var usageSummary: String { "\(attempts.count) / 50 free requests used by this app in the last 24 hours" }

    func checkAvailability() throws {
        let timestamp = now().timeIntervalSince1970
        let history = attempts
        var allowedAt = defaults.double(forKey: cooldownKey)
        if let last = history.last { allowedAt = max(allowedAt, last + Self.spacing) }
        if history.count >= Self.dailyLimit, let first = history.first { allowedAt = max(allowedAt, first + 86_400) }
        guard timestamp >= allowedAt else { throw waitError(until: Date(timeIntervalSince1970: allowedAt)) }
    }

    func reserveRequest() throws {
        try Task.checkCancellation()
        try checkAvailability()
        defaults.set(attempts + [now().timeIntervalSince1970], forKey: attemptsKey)
    }

    func checkPaidAvailability() throws {
        try Task.checkCancellation()
        let until = defaults.double(forKey: paidCooldownKey)
        if now().timeIntervalSince1970 < until { throw waitError(until: Date(timeIntervalSince1970: until)) }
    }

    /// Caps research requests, not Google's internal query count or dollar charges.
    func reserveResearchRequest() throws {
        try checkPaidAvailability()
        let key = "openrouter.research.attempts"
        let timestamp = now().timeIntervalSince1970
        let recent = (defaults.array(forKey: key) as? [Double] ?? []).filter { $0 > timestamp - 86_400 }
        guard recent.count < 20 else {
            throw RouterError.message("The 20 daily web-research requests are used. Try later, or ask for writing without web search.")
        }
        defaults.set(recent + [timestamp], forKey: key)
    }

    func recordRateLimit(retryAt: Date?, free: Bool = true) -> RouterError {
        let fallback = now().addingTimeInterval(60)
        let until = max(retryAt ?? fallback, now().addingTimeInterval(Self.spacing))
        let key = free ? cooldownKey : paidCooldownKey
        let next = max(until.timeIntervalSince1970, defaults.double(forKey: key))
        defaults.set(next, forKey: key)
        return waitError(until: Date(timeIntervalSince1970: next))
    }

    private func waitError(until date: Date) -> RouterError {
        let interval = max(1, ceil(date.timeIntervalSince(now())))
        let wait = interval < 60 ? "\(Int(interval)) seconds" : "\(Int(ceil(interval / 60))) minutes"
        return .message("OpenRouter usage is paused. Try again in \(wait).")
    }
}
