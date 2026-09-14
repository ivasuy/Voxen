import AppKit
import ApplicationServices

struct ApplicationDetector {
    @MainActor
    func capture(override: ContextMode? = nil) throws -> ApplicationContext {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw RouterError.message("Place the cursor in another application, then use your voice shortcut.")
        }
        let name = app.localizedName ?? "Unknown application"
        return ApplicationContext(appName: name, bundleIdentifier: app.bundleIdentifier,
                                  processIdentifier: app.processIdentifier,
                                  mode: Self.resolve(bundleIdentifier: app.bundleIdentifier, name: name,
                                                     override: override),
                                  modeIsOverride: override != nil)
    }

    @MainActor
    func captureDetails(_ context: ApplicationContext) async -> CapturedContext {
        var result = CapturedContext(application: context, selectedText: nil, accessibilityAvailable: AXIsProcessTrusted())
        guard result.accessibilityAvailable else { return result }
        if Self.isBrowser(bundleIdentifier: context.bundleIdentifier) {
            return await BrowserContextReader().capture(context)
        }
        result.selectedText = SelectedTextReader().read(processIdentifier: context.processIdentifier)
        return result
    }

    static func isBrowser(bundleIdentifier: String?) -> Bool {
        let browsers: Set<String> = ["com.apple.safari", "com.apple.safaritechnologypreview",
            "com.google.chrome", "com.google.chrome.canary", "org.chromium.chromium",
            "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser",
            "com.vivaldi.vivaldi", "com.operasoftware.opera", "org.mozilla.firefox",
            "app.zen-browser.zen", "com.kagi.kagimacos"]
        return bundleIdentifier.map { browsers.contains($0.lowercased()) } ?? false
    }

    static func resolve(bundleIdentifier: String?, name: String, website: WebsiteContext? = nil,
                        override: ContextMode? = nil) -> ContextMode {
        if let override { return override }
        // Browser destinations are interpreted by the LLM from the actual hostname, not a site registry.
        if isBrowser(bundleIdentifier: bundleIdentifier) { return .generic }
        let identifiers: [String: ContextMode] = [
            "com.todesktop.230313mzl4w4u92": .coding, "com.microsoft.vscode": .coding,
            "com.microsoft.vscodeinsiders": .coding, "com.apple.dt.xcode": .coding,
            "com.exafunction.windsurf": .coding, "dev.zed.zed": .coding,
            "com.apple.terminal": .terminal, "com.googlecode.iterm2": .terminal,
            "dev.warp.warp-stable": .terminal,
            "com.tinyspeck.slackmacgap": .messaging, "com.hnc.discord": .messaging,
            "com.apple.ichat": .messaging, "net.whatsapp.whatsapp": .messaging,
            "ru.keepcoder.telegram": .messaging, "org.telegram.desktop": .messaging,
            "notion.id": .document, "com.apple.notes": .document,
            "com.apple.iwork.pages": .document, "md.obsidian": .document
        ]
        if let identifier = bundleIdentifier?.lowercased(), let mode = identifiers[identifier] { return mode }
        let names: [ContextMode: Set<String>] = [
            .coding: ["cursor", "visual studio code", "code", "code - insiders", "xcode", "windsurf", "zed"],
            .terminal: ["terminal", "iterm", "iterm2", "warp"],
            .messaging: ["slack", "discord", "messages", "whatsapp", "telegram"],
            .document: ["notion", "notes", "pages", "obsidian"]
        ]
        return names.first(where: { $0.value.contains(name.lowercased()) })?.key ?? .generic
    }
}

/// Locates a browser's active web area without traversing its page content or reading address-field values.
struct BrowserContextReader {
    var attribute: (AXUIElement, String) -> CFTypeRef? = SelectedTextReader().attribute
    @MainActor private static var activatedProcesses = Set<pid_t>()

    struct Surface {
        var website: WebsiteContext?
        var webArea: AXUIElement?
        var focused: AXUIElement?
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func website(_ value: CFTypeRef?) -> WebsiteContext? {
        if let string = value as? String { return WebsiteContext.from(urlString: string) }
        if let url = value as? URL { return WebsiteContext.from(urlString: url.absoluteString) }
        return nil
    }

    func surface(app: AXUIElement, window: AXUIElement) -> Surface {
        let deadline = Date().addingTimeInterval(0.6)
        func get(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            Date() < deadline ? attribute(element, name) : nil
        }
        let focused = Self.element(get(app, kAXFocusedUIElementAttribute))
        var area: AXUIElement?
        var current = focused
        var reachedWindow = false
        for _ in 0..<32 {
            guard let element = current, Date() < deadline else { break }
            let role = get(element, kAXRoleAttribute) as? String
            if role == "AXWebArea" { area = element }
            if role == kAXWindowRole { reachedWindow = CFEqual(element, window); break }
            if role == kAXApplicationRole { break }
            current = Self.element(get(element, kAXParentAttribute))
        }
        if !reachedWindow { area = nil }
        if area == nil {
            // A highlighted document need not own keyboard focus. Find its outer web area through
            // native window containers. Never descend into AXWebArea (i.e. never traverse the DOM).
            var queue: [(AXUIElement, Int)] = [(window, 0)]
            var index = 0
            var candidates: [AXUIElement] = []
            while index < queue.count && index < 96 && Date() < deadline {
                let (element, depth) = queue[index]; index += 1
                if get(element, "AXHidden") as? Bool == true { continue }
                let role = get(element, kAXRoleAttribute) as? String ?? ""
                if role == "AXWebArea" { candidates.append(element); continue }
                if depth >= 10 || ["AXToolbar", "AXTabGroup", "AXMenu", "AXMenuBar", "AXSheet", "AXPopover"].contains(role) { continue }
                if let children = get(element, kAXChildrenAttribute) as? [AXUIElement] {
                    queue.append(contentsOf: children.prefix(max(0, 96 - queue.count)).map { ($0, depth + 1) })
                }
            }
            // Never guess between multiple page surfaces or choose an iframe URL.
            if candidates.count == 1 { area = candidates[0] }
        }
        let document = Self.website(get(window, kAXDocumentAttribute))
        let site = document ?? area.flatMap { Self.website(get($0, kAXURLAttribute)) }
        return Surface(website: site, webArea: area, focused: focused)
    }

    @MainActor
    func capture(_ context: ApplicationContext) async -> CapturedContext {
        var result = CapturedContext(application: context, selectedText: nil, accessibilityAvailable: AXIsProcessTrusted())
        guard result.accessibilityAvailable else { return result }
        let app = AXUIElementCreateApplication(context.processIdentifier)
        guard let window = Self.element(attribute(app, kAXFocusedWindowAttribute)) else { return result }
        // Used only in memory to reject navigation while the browser initializes its AX tree.
        let originalTitle = attribute(window, kAXTitleAttribute) as? String
        let originalSite = Self.website(attribute(window, kAXDocumentAttribute))
        let chromium = !["com.apple.safari", "com.apple.safaritechnologypreview", "org.mozilla.firefox",
                         "app.zen-browser.zen", "com.kagi.kagimacos"].contains(context.bundleIdentifier?.lowercased() ?? "")
        let activationStarted = Date()
        let firstActivation = chromium && !Self.activatedProcesses.contains(context.processIdentifier)
        if firstActivation {
            Self.activatedProcesses = Self.activatedProcesses.filter { NSRunningApplication(processIdentifier: $0) != nil }
            Self.activatedProcesses.insert(context.processIdentifier)
            // Chromium debounces this request for two seconds on current macOS. Request once, not
            // every poll (which would restart the delay). Never turn other assistive tools' AX mode off.
            _ = attribute(app, kAXRoleAttribute)
            AXUIElementSetMessagingTimeout(app, 0.1)
            _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        let deadline = Date().addingTimeInterval(firstActivation ? 3.5 : 1.0)
        repeat {
            guard !Task.isCancelled else { return result }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processIdentifier,
                  let activeWindow = Self.element(attribute(app, kAXFocusedWindowAttribute)), CFEqual(window, activeWindow),
                  attribute(window, kAXTitleAttribute) as? String == originalTitle else {
                result.destinationChanged = true; return result
            }
            let snapshot = surface(app: app, window: window)
            if let originalSite, let site = snapshot.website, site != originalSite {
                result.destinationChanged = true; return result
            }
            let reader = SelectedTextReader()
            let focusedSelection = snapshot.focused.flatMap { reader.read(focused: $0) }
            // Do not read an enclosing selection when the focused field is secure.
            let secure = snapshot.focused.map { attribute($0, kAXSubroleAttribute) as? String == "AXSecureTextField" } ?? false
            let selection = secure ? nil : focusedSelection ?? snapshot.webArea.flatMap { reader.read(focused: $0) }
            let warmed = !firstActivation || Date().timeIntervalSince(activationStarted) >= 2.2
            if snapshot.website != nil && (selection != nil || warmed) {
                result.application.website = snapshot.website
                result.selectedText = selection
                return result
            }
            if Date() >= deadline {
                result.application.website = snapshot.website
                result.selectedText = selection
                return result
            }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return result }
        } while true
    }
}

/// Opt-in diagnostic in the real app identity. Does not instantiate AppState, access keys, record, or call APIs.
/// It refuses selection reads unless Chrome's focused window is our synthetic fixture.
@MainActor
enum BrowserCaptureProbe {
    static func run() async {
        var report: [String: Any] = ["accessibilityTrusted": AXIsProcessTrusted()]
        let destination = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("browser-context-probe.json")
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        guard AXIsProcessTrusted(), let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { return }
        let app = AXUIElementCreateApplication(chrome.processIdentifier)
        func get(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.2)
            var result: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
            report["error_" + name] = error.rawValue
            return error == .success ? result : nil
        }
        guard let windowValue = get(app, kAXFocusedWindowAttribute), CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return }
        let window = unsafeDowncast(windowValue, to: AXUIElement.self)
        guard let title = get(window, kAXTitleAttribute) as? String, title.hasPrefix("Voice Intent Router Capture Fixture") else {
            report["fixtureFocused"] = false; return
        }
        report["fixtureFocused"] = true
        chrome.activate(options: [])
        try? await Task.sleep(for: .milliseconds(200))
        if let focusedValue = get(app, kAXFocusedUIElementAttribute), CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
            report["focusedRole"] = get(focused, kAXRoleAttribute) as? String ?? "unavailable"
        }
        let started = Date()
        let capture = await BrowserContextReader().capture(ApplicationContext(appName: "Google Chrome", bundleIdentifier: chrome.bundleIdentifier,
                                                                             processIdentifier: chrome.processIdentifier, mode: .generic))
        report["captureMilliseconds"] = Int(Date().timeIntervalSince(started) * 1000)
        report["destinationChanged"] = capture.destinationChanged
        report["hostMatchesFixture"] = capture.application.website?.host == "127.0.0.1"
        let selection = capture.selectedText
        report["selectedCharacters"] = selection?.count ?? 0
        report["selectionMatchesFixture"] = selection?.contains("Could you send the revised draft on Monday?") == true
            && selection?.contains("Please confirm the review time.") == true
    }
}
