import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
    let appName: String
    let websiteHost: String?
    let mode: ContextMode
    var source: String { websiteHost ?? appName }
}

/// Stores only completed generated responses. Never receives audio, transcript or selection.
@MainActor
final class ResponseHistory: ObservableObject {
    static let limit = 100
    @Published private(set) var entries: [HistoryEntry]
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "responseHistoryEnabled") } }
    private let defaults: UserDefaults
    private static let key = "responseHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "responseHistoryEnabled") as? Bool ?? true
        entries = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) }
            .map { Array($0.prefix(Self.limit)) } ?? []
    }

    func append(_ generated: GeneratedText, appName: String, websiteHost: String?, mode: ContextMode) {
        guard isEnabled else { return }
        entries.insert(HistoryEntry(id: UUID(), createdAt: Date(), text: generated.text,
                                    appName: appName, websiteHost: websiteHost, mode: mode), at: 0)
        entries = Array(entries.prefix(Self.limit))
        persist()
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; persist() }
    func clear() { entries = []; defaults.removeObject(forKey: Self.key) }
    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
