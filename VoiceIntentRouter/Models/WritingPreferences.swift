import Foundation

enum WritingDepth: String, Codable, CaseIterable, Identifiable {
    case precise = "Precise", balanced = "Balanced", elaborate = "Elaborate"
    var id: String { rawValue }
    var guidance: String {
        switch self {
        case .precise: return "Get to the point. Include only what the task needs."
        case .balanced: return "Develop the main idea with useful supporting detail."
        case .elaborate: return "Explore implications, reasoning and actionable detail without padding."
        }
    }
}
enum WritingAssumptions: String, Codable, CaseIterable, Identifiable {
    case grounded = "No assumptions", suggested = "Suggest options", exploratory = "Explore possibilities"
    var id: String { rawValue }
    var guidance: String {
        switch self {
        case .grounded: return "Use supplied facts. Do not invent features, a stack or progress."
        case .suggested: return "For planning and coding prompts, propose sensible features or a stack as optional suggestions."
        case .exploratory: return "For planning and coding prompts, develop a proposed feature set, stack and tradeoffs; label assumptions."
        }
    }
}
enum WritingTone: String, Codable, CaseIterable, Identifiable {
    case natural = "Natural", professional = "Professional", conversational = "Conversational"
    case humorous = "Humorous", quirky = "Quirky", direct = "Direct"
    var id: String { rawValue }
}
enum WritingFormat: String, Codable, CaseIterable, Identifiable {
    case adaptive = "Adapt to task", paragraphs = "Paragraphs", bullets = "Bullet points", numbered = "Numbered steps"
    var id: String { rawValue }
}
enum WritingEmojis: String, Codable, CaseIterable, Identifiable {
    case none = "None", light = "Occasional", expressive = "Expressive"
    var id: String { rawValue }
}
enum WritingHashtags: String, Codable, CaseIterable, Identifiable {
    case none = "None", few = "Up to 3 relevant tags"
    var id: String { rawValue }
}
struct WritingStyle: Codable, Equatable {
    var depth: WritingDepth = .balanced
    var assumptions: WritingAssumptions = .grounded
    var tone: WritingTone = .natural
    var format: WritingFormat = .adaptive
    var emojis: WritingEmojis = .none
    var hashtags: WritingHashtags = .none
    var targetWords = 0
    var language = ""
    var instructions = ""
    var payload: [String: Any] {
        ["detail": depth.rawValue, "detail_guidance": depth.guidance,
         "assumptions": assumptions.rawValue, "assumption_guidance": assumptions.guidance,
         "tone": tone.rawValue, "format": format.rawValue, "emojis": emojis.rawValue,
         "hashtags_for_social_posts_only": hashtags.rawValue,
         "target_words": targetWords, "language": language, "preferences": instructions]
    }
    func validate() throws {
        guard (0...1500).contains(targetWords), language.count <= 80, instructions.count <= 1500 else {
            throw RouterError.message("Use 0–1,500 target words, a language under 80 characters and preferences under 1,500 characters.")
        }
    }
}
struct WriterProfile: Codable, Equatable {
    var enabled = false
    var name = ""
    var role = ""
    var work = ""
    var audience = ""
    var stack = ""
    var avoid = ""
    var samples = ""
    var payload: [String: Any] {
        ["name": name, "role": role, "work_and_interests": work, "audience": audience,
         "preferred_stack": stack, "avoid": avoid, "writing_samples_style_only": samples]
    }
}
enum WritingDestinationKind: String, Codable, CaseIterable, Identifiable {
    case website = "Website", app = "Application", mode = "Mode"
    var id: String { rawValue }
}
struct WritingDestination: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var kind: WritingDestinationKind = .website
    var target: String
    var enabled = false
    var customStyle = false
    var style = WritingStyle()
    var characterBudget = 0
    var longPosts = false
    var isX: Bool { id == "x" }
    var effectiveCharacterBudget: Int { isX ? (longPosts ? 25000 : 280) : characterBudget }
    static var presets: [Self] {
        [Self(id: "x", name: "X", target: "x.com", characterBudget: 280),
         Self(id: "linkedin", name: "LinkedIn", target: "linkedin.com", characterBudget: 3000),
         Self(id: "instagram", name: "Instagram", target: "instagram.com", characterBudget: 2200),
         Self(id: "gmail", name: "Gmail", target: "mail.google.com"),
         Self(id: "coding", name: "Coding prompts", kind: .mode, target: ContextMode.coding.rawValue)]
    }
    func matches(_ context: VoiceContext) -> Bool {
        guard enabled else { return false }
        switch kind {
        case .website:
            guard let host = context.website?.host.lowercased() else { return false }
            let aliases = isX ? ["x.com", "twitter.com"] : [target.lowercased()]
            return aliases.contains { host == $0 || host.hasSuffix("." + $0) }
        case .app:
            return target.caseInsensitiveCompare(context.bundleIdentifier ?? "") == .orderedSame
                || target.caseInsensitiveCompare(context.appName) == .orderedSame
        case .mode: return context.mode.rawValue == target
        }
    }
}
struct WritingPreferences: Codable, Equatable {
    var style = WritingStyle()
    var profile = WriterProfile()
    var destinations = WritingDestination.presets

    func matchingDestination(_ context: VoiceContext) -> WritingDestination? {
        // Specific websites win over native app names, then mode defaults. Longest host wins.
        destinations.filter { $0.matches(context) }.sorted {
            let order: [WritingDestinationKind: Int] = [.website: 0, .app: 1, .mode: 2]
            if order[$0.kind] != order[$1.kind] { return order[$0.kind]! < order[$1.kind]! }
            return $0.target.count > $1.target.count
        }.first
    }
    func resolvedStyle(for context: VoiceContext) -> WritingStyle {
        let destination = matchingDestination(context)
        return destination?.customStyle == true ? destination!.style : style
    }
    func instructions(for context: VoiceContext) -> String {
        let active = resolvedStyle(for: context)
        var rules = "\n\nACTIVE SAVED SETTINGS FOR THIS REQUEST\n"
        rules += "Use these unless the current spoken instruction explicitly overrides them.\n"
        rules += "Detail: \(active.depth.rawValue). \(active.depth.guidance)\n"
        rules += "Tone: \(active.tone.rawValue). Format: \(active.format.rawValue). Emojis: \(active.emojis.rawValue). Social hashtags: \(active.hashtags.rawValue).\n"
        switch active.assumptions {
        case .grounded:
            rules += "NO ASSUMPTIONS: Do not pick unstated frameworks, storage technologies, architectures, integrations or extra features, even in a coding prompt. A task tracker does not imply SwiftData, a database, a menu bar or a cloud service. Leave unspecified choices open; ask the coding agent to inspect the project or confirm material choices. A supplied preferred stack can guide suggestions, but does not imply related frameworks.\n"
        case .suggested:
            rules += "SUGGEST OPTIONS: In plans and coding prompts, offer a small set of useful feature/stack options. Label them optional proposals, not established requirements. Inspect existing conventions first.\n"
        case .exploratory:
            rules += "EXPLORE POSSIBILITIES: In plans and coding prompts, propose a coherent feature set, stack and tradeoffs. Clearly mark the whole plan's extra choices as proposed assumptions, not facts or prior user requirements. Respect supplied constraints.\n"
        }
        if active.targetWords > 0 {
            rules += "Aim for \(active.targetWords) words. Unless speech explicitly asks otherwise, revise an overlong draft to stay within about \(Int(Double(active.targetWords) * 1.2)) words; do not pad a sparse update to reach the target.\n"
        }
        if let destination = matchingDestination(context), destination.effectiveCharacterBudget > 0 {
            rules += "For a post/comment/caption here, stay within \(destination.effectiveCharacterBudget) characters including spaces, emojis and hashtags; this beats the word target. Do not create a thread.\n"
        }
        rules += "Profile examples inform style, not the facts of this task. Do not add unrequested promises, progress updates or calls to action. Return only the requested text."
        return rules
    }
    func payload(for context: VoiceContext) -> [String: Any] {
        let destination = matchingDestination(context)
        let selectedStyle = resolvedStyle(for: context)
        var result = selectedStyle.payload
        result["source"] = destination?.name ?? "Writing defaults"
        if let destination, destination.effectiveCharacterBudget > 0 {
            result["character_budget"] = destination.effectiveCharacterBudget
            result["character_budget_scope"] = "Posts, comments or captions on this destination; not an unrequested thread. Count punctuation, spaces, emojis, hashtags and citations. Character budgets outrank word targets."
        }
        return result
    }
    func validated() throws -> Self {
        var copy = self
        try style.validate()
        guard profile.name.count <= 100, profile.role.count <= 200, profile.work.count <= 1500,
              profile.audience.count <= 500, profile.stack.count <= 500, profile.avoid.count <= 500,
              profile.samples.count <= 6000, destinations.count <= 20 else {
            throw RouterError.message("Profile fields or platform count exceed their limits. Shorten your inputs (samples: 6,000 characters; platforms: 20).")
        }
        var targets = Set<String>()
        var identifiers = Set<String>()
        for index in copy.destinations.indices {
            var item = copy.destinations[index]
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.target = item.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.id.isEmpty, identifiers.insert(item.id).inserted,
                  !item.name.isEmpty, item.name.count <= 60, !item.target.isEmpty, item.target.count <= 200,
                  (0...25000).contains(item.characterBudget) else {
                throw RouterError.message("Each platform needs a name, a destination and a character budget between 0 and 25,000.")
            }
            if item.kind == .website {
                guard let host = WebsiteContext.from(urlString: item.target.contains("://") ? item.target : "https://" + item.target)?.host,
                      host.contains("."), !host.contains(where: \.isWhitespace) else {
                    throw RouterError.message("Enter a valid website hostname, such as example.com.")
                }
                item.target = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                if item.isX { item.target = "x.com" }
            }
            if item.kind == .mode, ContextMode(rawValue: item.target) == nil {
                throw RouterError.message("Choose a valid mode for the writing preset.")
            }
            guard targets.insert(item.kind.rawValue + ":" + item.target.lowercased()).inserted else {
                throw RouterError.message("A preset already exists for that destination.")
            }
            try item.style.validate()
            copy.destinations[index] = item
        }
        return copy
    }
}
@MainActor final class WritingPreferencesStore: ObservableObject {
    @Published private(set) var saved: WritingPreferences
    private let defaults: UserDefaults
    static let key = "writingPreferences.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(WritingPreferences.self, from: $0) }
            .flatMap { try? $0.validated() } ?? WritingPreferences()
    }
    func save(_ preferences: WritingPreferences) throws {
        let validated = try preferences.validated()
        let encoded = try JSONEncoder().encode(validated)
        defaults.set(encoded, forKey: Self.key)
        saved = validated
    }
}
