// Renders synthetic UI only: no microphone, Keychain, window capture, or API access.
import AppKit
import SwiftUI

@main
struct OverlayPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for dark in [false, true] {
            let view = VStack(spacing: 10) {
                sample(.listening, destination: "X", mode: "Post", level: 0.7)
                sample(.listening, destination: "Cursor", mode: "Prompt", level: 0.2, selected: true)
                sample(.transcribing, destination: "LinkedIn", mode: "Post")
                sample(.transforming, destination: "Chrome", mode: "Site unknown")
                sample(.done, destination: "Slack", mode: "Reply")
                sample(.error, destination: "X", mode: "Post", detail: "Website access is unavailable. Enable Accessibility in Settings, or choose Social from the menu bar.")
            }
            .padding(20)
            .background(Color(nsColor: .underPageBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: "build/overlay-preview-\(dark ? "dark" : "light").png"))

            let settings = AppSettings(defaults: UserDefaults(suiteName: "dev.voxen.preview")!,
                                       readSecret: { _ in "synthetic-preview-key" }, saveSecret: { _, _ in })
            let settingsView = NSHostingView(rootView: SettingsView(settings: settings)
                .frame(width: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light))
            settingsView.appearance = hosting.appearance
            settingsView.frame = NSRect(origin: .zero, size: settingsView.fittingSize)
            let window = NSWindow(contentRect: settingsView.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = hosting.appearance
            window.contentView = settingsView
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            settingsView.layoutSubtreeIfNeeded()
            guard let settingsBitmap = settingsView.bitmapImageRepForCachingDisplay(in: settingsView.bounds) else {
                fatalError("No settings bitmap")
            }
            settingsView.cacheDisplay(in: settingsView.bounds, to: settingsBitmap)
            try settingsBitmap.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "build/settings-preview-\(dark ? "dark" : "light").png"))
        }
        for phase: RouterPhase in [.idle, .listening, .transcribing, .transforming, .done, .error] {
            let content = NSHostingView(rootView: sample(phase, destination: "", mode: "", detail: String(repeating: "Error details. ", count: 100)))
            guard content.fittingSize == NSSize(width: 160, height: 54) else {
                fatalError("Status changed capsule dimensions: \(phase)")
            }
            // Individual native status captures for the landing page. Synthetic values only.
            let names: [RouterPhase: String] = [.listening: "listening", .transforming: "writing", .done: "copied"]
            if let name = names[phase] {
                let renderer = ImageRenderer(content: sample(phase, destination: "", mode: "", level: 0.7)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 6
                guard let rendered = renderer.cgImage else { fatalError("No status render") }
                let bitmap = NSBitmapImageRep(cgImage: rendered)
                try bitmap.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "build/status-\(name).png"))
            }
        }
        let listening = NSHostingView(rootView: sample(.listening, destination: "X", mode: "Post"))
        let size = listening.fittingSize
        guard size.width <= 160, size.height <= 54 else { fatalError("Overlay too large: \(size)") }
        print("PASS: listening overlay \(Int(size.width)) × \(Int(size.height)); light/dark synthetic previews rendered")
    }

    @MainActor static func sample(_ phase: RouterPhase, destination: String, mode: String,
                                 level: Float = 0, selected: Bool = false, detail: String = "") -> some View {
        OverlayContent(phase: phase, audioLevel: level, detail: detail)
    }
}
