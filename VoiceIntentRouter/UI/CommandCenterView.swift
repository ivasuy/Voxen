import SwiftUI
import AppKit

enum CommandPage: String, CaseIterable, Identifiable {
    case mode = "Mode", writing = "Writing", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .mode: return "slider.horizontal.3"
        case .writing: return "textformat"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor final class CommandNavigation: ObservableObject {
    @Published var page: CommandPage = .mode
}

struct CommandCenterView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: ResponseHistory
    @ObservedObject var navigation: CommandNavigation
    @ObservedObject var writing: WritingPreferencesStore
    var initialWritingTab: WritingTab = .style
    var isBusy = false
    var errorDetail: String? = nil
    var onCancel: () -> Void = {}
    var onSave: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    if let logo = VoxenStyle.logo {
                        Image(nsImage: logo).resizable().scaledToFit().frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                    }
                    Text("Voxen").font(.system(size: 18, weight: .semibold, design: .monospaced))
                }.padding(.horizontal, 8).padding(.top, 6)
                VStack(spacing: 5) {
                    ForEach(CommandPage.allCases) { page in
                        Button { navigation.page = page } label: {
                            Label(page.rawValue, systemImage: page.symbol)
                                .font(.system(size: 13, weight: navigation.page == page ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(navigation.page == page ? VoxenStyle.action.opacity(0.11) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(navigation.page == page ? VoxenStyle.action : .primary)
                        .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
                    }
                }
                Spacer()
                if isBusy {
                    Button("Cancel request", action: onCancel).font(.caption)
                }
            }
            .padding(16).frame(width: 170)
            .background(Color(nsColor: .controlBackgroundColor))
            Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
            VStack(spacing: 0) {
                if let errorDetail {
                    Label(errorDetail, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(Color.orange.opacity(0.10))
                        .textSelection(.enabled)
                }
                ZStack(alignment: .topLeading) {
                    // Keep the settings draft alive when moving between sidebar destinations.
                    ScrollView { SettingsView(settings: settings, onSave: onSave) }
                        .opacity(navigation.page == .settings ? 1 : 0)
                        .allowsHitTesting(navigation.page == .settings)
                        .disabled(navigation.page != .settings)
                        .accessibilityHidden(navigation.page != .settings)
                    WritingView(store: writing, initialTab: initialWritingTab)
                        .opacity(navigation.page == .writing ? 1 : 0)
                        .allowsHitTesting(navigation.page == .writing)
                        .disabled(navigation.page != .writing)
                        .accessibilityHidden(navigation.page != .writing)
                    if navigation.page == .mode { modePage }
                    if navigation.page == .history { HistoryView(history: history) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 740, minHeight: 580)
        .tint(VoxenStyle.action)
    }

    private var modePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose mode").font(.system(size: 24, weight: .semibold))
                    Text("Set how Voxen shapes your words.").font(.callout).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    modeRow(nil, title: "Auto", symbol: "sparkle", subtitle: "Adapt to the app, website and selected text.")
                    ForEach(ContextMode.allCases) { mode in
                        modeRow(mode, title: mode.label, symbol: mode.symbol, subtitle: mode.summary)
                    }
                }.disabled(isBusy)
            }.padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func modeRow(_ mode: ContextMode?, title: String, symbol: String, subtitle: String) -> some View {
        let selected = settings.modeOverride == mode
        return Button { settings.modeOverride = mode; onSave() } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 24)
                    .foregroundStyle(selected ? VoxenStyle.action : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(VoxenStyle.action) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? VoxenStyle.action.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HistoryView: View {
    @ObservedObject var history: ResponseHistory
    @State private var copiedID: UUID?
    @State private var errorMessage: String?
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("History").font(.system(size: 24, weight: .semibold))
                Spacer()
                if !history.entries.isEmpty {
                    if confirmClear {
                        Button("Cancel") { confirmClear = false }
                        Button("Delete all", role: .destructive) { history.clear(); confirmClear = false }
                    } else {
                        Button("Clear") { confirmClear = true }
                    }
                }
            }
            Toggle("Keep history on this Mac", isOn: $history.isEnabled).toggleStyle(.switch).controlSize(.small)
            Text("Last 100 responses. No audio or highlighted source text.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            if history.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Your responses, here").font(.headline)
                    Text("Speak in another app. Completed responses will appear here.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(history.entries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 7) {
                                    Image(systemName: entry.websiteHost == nil ? "app" : "globe")
                                    Text(entry.source).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .foregroundStyle(.secondary)
                                }.font(.caption)
                                Text(entry.text).font(.system(size: 13)).lineSpacing(4)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Button {
                                        do {
                                            try ClipboardManager().write(entry.text)
                                            copiedID = entry.id; errorMessage = nil
                                        } catch { errorMessage = "Could not copy. Try again." }
                                    } label: {
                                        Label(copiedID == entry.id ? "Copied" : "Copy", systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                                    }
                                    .task(id: copiedID) {
                                        guard copiedID == entry.id else { return }
                                        do { try await Task.sleep(for: .seconds(2)); copiedID = nil } catch {}
                                    }
                                    Spacer()
                                    Button { history.remove(entry.id) } label: { Image(systemName: "trash") }
                                        .help("Delete response").accessibilityLabel("Delete response from \(entry.source)")
                                }.controlSize(.small)
                            }
                            Divider()
                        }
                    }
                }
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Keeps the command center reactive without coupling preview fixtures to microphone or keys.
struct LiveCommandCenter: View {
    @ObservedObject var state: AppState
    var onSave: () -> Void
    var body: some View {
        CommandCenterView(settings: state.settings, history: state.history, navigation: state.navigation, writing: state.writing,
                          isBusy: state.phase.isBusy, errorDetail: state.phase == .error ? state.detail : nil,
                          onCancel: state.cancel, onSave: onSave)
    }
}
