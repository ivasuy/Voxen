import AppKit
import SwiftUI

private struct PreviewProvider: LLMProvider {
    let text: String
    func generate(instructions: String, input: String) async throws -> String { text }
}

@main struct CommandCenterPreview {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "dev.voxen.command-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, readSecret: { _ in "synthetic-preview-key" }, saveSecret: { _, _ in })
        let history = ResponseHistory(defaults: defaults)
        let writing = WritingPreferencesStore(defaults: defaults)
        var preferences = writing.saved
        preferences.profile.enabled = true
        preferences.profile.name = "Alex"
        preferences.profile.role = "Developer and open-source builder"
        preferences.profile.work = "Small tools that make everyday development less repetitive."
        preferences.profile.samples = "Built a small tool this weekend. One repetitive task, a little less repetitive. Sharing what worked and what I would change next."
        preferences.destinations[0].enabled = true
        preferences.destinations[0].customStyle = true
        preferences.destinations[0].style.tone = .quirky
        preferences.destinations[0].style.targetWords = 40
        try writing.save(preferences)
        let samples: [(String, String?, ContextMode, String)] = [
            ("Cursor", nil, .coding, "Simplify the selected implementation while preserving behavior and public interfaces. Run the relevant tests and report any failures."),
            ("Chrome", "x.com", .social, "Benchmarks show what coding models can score. Production work shows what they can actually handle. We need to measure both."),
            ("Slack", nil, .messaging, "Tomorrow morning is more realistic. I'd rather give it the extra time than rush it today.")
        ]
        for (app, host, mode, text) in samples {
            let output = try await IntentTransformer(provider: PreviewProvider(text: text))
                .transform(VoiceContext(appName: app, bundleIdentifier: nil, mode: mode, selectedText: nil, transcript: "Synthetic preview"))
            history.append(output, appName: app, websiteHost: host, mode: mode)
        }
        for dark in [false, true] {
            for page in CommandPage.allCases {
                let navigation = CommandNavigation()
                navigation.page = page
                try render(CommandCenterView(settings: settings, history: history, navigation: navigation, writing: writing),
                           name: page.rawValue.lowercased(), dark: dark)
            }
            for tab in [WritingTab.profile, .platforms] {
                let navigation = CommandNavigation(); navigation.page = .writing
                try render(CommandCenterView(settings: settings, history: history, navigation: navigation, writing: writing, initialWritingTab: tab),
                           name: "writing-" + (tab == .profile ? "profile" : "platforms"), dark: dark)
            }
        }
        let heroNavigation = CommandNavigation()
        heroNavigation.page = .mode
        try renderRetina(CommandCenterView(settings: settings, history: history, navigation: heroNavigation, writing: writing),
                         name: "hero", dark: true)
        history.clear()
        let navigation = CommandNavigation()
        navigation.page = .history
        try render(CommandCenterView(settings: settings, history: history, navigation: navigation, writing: writing), name: "empty", dark: false)
        try render(CommandCenterView(settings: settings, history: history, navigation: navigation, writing: writing,
                                     errorDetail: "Website access is unavailable. Enable Accessibility in Settings, then try again."), name: "error", dark: false)
        print("PASS: command center pages rendered in light and dark; empty and error states rendered with synthetic data")
    }

    @MainActor static func render<V: View>(_ content: V, name: String, dark: Bool, width: CGFloat = 780, height: CGFloat = 640) throws {
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Missing bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "build/command-\(name)-\(dark ? "dark" : "light").png"))
    }

    @MainActor static func renderRetina<V: View>(_ content: V, name: String, dark: Bool) throws {
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 640)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3120, pixelsHigh: 2560,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Missing Retina bitmap") }
        bitmap.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "build/command-\(name)-\(dark ? "dark" : "light").png"))
    }
}
