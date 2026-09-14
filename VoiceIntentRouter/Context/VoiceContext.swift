import Foundation

struct VoiceContext {
    let appName: String
    let bundleIdentifier: String?
    let mode: ContextMode
    let selectedText: String?
    let transcript: String
    var website: WebsiteContext? = nil
    var modeIsOverride = false
    var writingPreferences: WritingPreferences? = nil
}

struct ApplicationContext {
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let mode: ContextMode
    var website: WebsiteContext? = nil
    var modeIsOverride = false
    var displayName: String { website?.host ?? appName }
}

struct CapturedContext {
    var application: ApplicationContext
    var selectedText: String?
    var accessibilityAvailable: Bool
    var destinationChanged = false
}

/// Keeps only a hostname, never the page path, query, fragment, title, or browsing history.
struct WebsiteContext: Equatable {
    let host: String

    static func from(urlString: String) -> Self? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty else { return nil }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        return Self(host: host)
    }
}
