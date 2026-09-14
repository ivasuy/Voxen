import Foundation

enum ContextMode: String, CaseIterable, Identifiable, Codable {
    case coding, messaging, social, terminal, document, generic
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .coding: return "Turn intent into an actionable engineering prompt."
        case .messaging: return "Write a natural reply that fits the conversation."
        case .social: return "Shape a thought into a post, caption or comment."
        case .terminal: return "Explain output or suggest a command. Never execute it."
        case .document: return "Draft, rewrite and clarify prose."
        case .generic: return "Refine writing without assuming a specific destination."
        }
    }
    var shortTitle: String {
        switch self {
        case .coding: return "Prompt"
        case .messaging: return "Reply"
        case .social: return "Post"
        case .terminal: return "Terminal"
        case .document: return "Document"
        case .generic: return "Auto"
        }
    }
    var title: String {
        switch self {
        case .coding: return "Engineering Prompt"
        case .messaging: return "Conversational Reply"
        case .social: return "Social Post"
        case .terminal: return "Terminal Help"
        case .document: return "Document"
        case .generic: return "Contextual Writing"
        }
    }
    var symbol: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .messaging: return "bubble.left.and.bubble.right"
        case .social: return "quote.bubble"
        case .terminal: return "terminal"
        case .document: return "doc.text"
        case .generic: return "text.alignleft"
        }
    }
}
