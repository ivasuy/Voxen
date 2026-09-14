import SwiftUI
import AppKit

/// Native SF typography, one green accent family, and an opaque status surface.
enum VoxenStyle {
    static let charcoal = Color(red: 0.125, green: 0.145, blue: 0.133)
    static let mint = Color(red: 0.384, green: 0.875, blue: 0.690)
    static let ink = Color(red: 0.925, green: 0.949, blue: 0.937)
    static let action = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.384, green: 0.875, blue: 0.690, alpha: 1)
            : NSColor(red: 0.02, green: 0.39, blue: 0.27, alpha: 1)
    })
    static var logo: NSImage? {
        Bundle.main.url(forResource: "voxen-logo-v1", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var permissions = PermissionManager()
    @State private var draft: SettingsDraft
    @State private var feedback = ""
    @State private var saveFailed = false
    private let onSave: () -> Void
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(settings: AppSettings, onSave: @escaping () -> Void = {}) {
        self.settings = settings
        self.onSave = onSave
        _draft = State(initialValue: settings.saved)
    }

    private var hasChanges: Bool { draft.normalized != settings.saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.system(size: 24, weight: .semibold))
            VStack(spacing: 14) {
                row("AssemblyAI key") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API key", text: $draft.assemblyAIKey)
                        Link("Get your AssemblyAI key", destination: URL(string: "https://www.assemblyai.com/dashboard/signup")!)
                            .font(.caption)
                    }
                }
                row("OpenRouter key") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API key", text: $draft.openRouterKey)
                        Link("Get your OpenRouter key", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                            .font(.caption)
                    }
                }
                row("Model") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Writing model", selection: $draft.model) {
                            ForEach(OpenRouterProvider.models) { model in Text(model.name).tag(model.id) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("Writing model")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(OpenRouterProvider.option(draft.model)?.priceSummary ?? "")
                            Text("Planning & optional search: Gemini Flash-Lite. Search costs extra.")
                        }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                row("Shortcut") {
                    Picker("Modifier keys", selection: Binding(
                        get: { draft.shortcut.modifiers },
                        set: { draft.shortcut = VoiceShortcut(keyCode: draft.shortcut.keyCode, modifiers: $0) }
                    )) {
                        ForEach(VoiceShortcut.modifierChoices, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }.labelsHidden().frame(width: 84, alignment: .leading)
                        .accessibilityLabel("Shortcut modifiers")
                    Picker("Shortcut key", selection: Binding(
                        get: { draft.shortcut.keyCode },
                        set: { draft.shortcut = VoiceShortcut(keyCode: $0, modifiers: draft.shortcut.modifiers) }
                    )) {
                        ForEach(VoiceShortcut.keyChoices, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }.labelsHidden().frame(width: 100, alignment: .leading)
                        .accessibilityLabel("Shortcut key")
                    Spacer(minLength: 0)
                }
            }.textFieldStyle(.roundedBorder)
            Divider()
            OnboardingView(permissions: permissions)
            Divider()
            HStack {
                Text(saveFailed ? feedback : (hasChanges ? "" : feedback))
                    .font(.caption).foregroundStyle(saveFailed ? Color.orange : Color.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!hasChanges)
            }
        }
        .font(.system(size: 12))
        .tint(VoxenStyle.action)
        .frame(maxWidth: 520)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .center)
        .onReceive(refresh) { _ in permissions.refresh() }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).frame(width: 110, alignment: .leading)
            HStack(spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func save() {
        do {
            try settings.save(draft)
            draft = settings.saved
            feedback = "Saved"
            saveFailed = false
            onSave()
        } catch {
            saveFailed = true
            feedback = error.localizedDescription
        }
    }
}
