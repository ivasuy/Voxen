import SwiftUI

enum WritingTab: String, CaseIterable, Identifiable {
    case style = "Style", profile = "About you", platforms = "Platforms"
    var id: String { rawValue }
}

struct WritingView: View {
    @ObservedObject var store: WritingPreferencesStore
    @State private var draft: WritingPreferences
    @State private var tab: WritingTab
    @State private var selectedDestination = "x"
    @State private var errorMessage: String?
    @State private var confirmClear = false

    init(store: WritingPreferencesStore, initialTab: WritingTab = .style) {
        self.store = store
        _draft = State(initialValue: store.saved)
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Writing").font(.system(size: 24, weight: .semibold))
                Spacer()
                Text(draft == store.saved ? "Saved" : "Unsaved changes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Writing section", selection: $tab) {
                ForEach(WritingTab.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Writing section")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .style:
                        sectionHeading("Your default voice", "Used everywhere unless a platform or spoken request overrides it.")
                        WritingStyleEditor(style: $draft.style)
                    case .profile: profileForm
                    case .platforms: platformForm
                    }
                }.padding(.vertical, 4).padding(.trailing, 4)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                if draft != store.saved {
                    Button("Discard") { draft = store.saved; errorMessage = nil }
                }
                Spacer()
                Button("Save") {
                    do { try store.save(draft); draft = store.saved; errorMessage = nil }
                    catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).tint(.accentColor)
                .disabled(draft == store.saved)
            }
        }.padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Make it sound like you", "Optional context and examples, not a biography to paste into every response.")
            Toggle("Use my profile when writing", isOn: $draft.profile.enabled)
                .toggleStyle(.switch).controlSize(.small)
            Text("Saved on this Mac, unencrypted. When enabled, these fields go to OpenRouter with voice requests, never to web search. Add only information you’re comfortable sharing.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            WritingField("Name") { TextField("What should we call you?", text: $draft.profile.name) }
            WritingField("What you do") { TextField("Developer, founder, designer…", text: $draft.profile.role) }
            WritingTextArea(title: "Work & interests", hint: "Projects, topics and experience you want the writer to know. Up to 1,500 characters.", text: $draft.profile.work, height: 70)
            WritingField("Audience") { TextField("Who you write for", text: $draft.profile.audience) }
            WritingField("Preferred stack") { TextField("Optional, for engineering suggestions", text: $draft.profile.stack) }
            WritingField("Avoid") { TextField("Words, claims or habits you dislike", text: $draft.profile.avoid) }
            WritingTextArea(title: "Writing samples", hint: "Paste a few posts you wrote, separated by blank lines. Used for voice and rhythm, not as reusable facts. Up to 6,000 characters.", text: $draft.profile.samples, height: 120)
            HStack {
                if confirmClear {
                    Button("Cancel") { confirmClear = false }
                    Button("Clear profile", role: .destructive) {
                        draft.profile = WriterProfile(); confirmClear = false
                    }
                    Text("Save to remove stored fields.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Clear profile…") { confirmClear = true }
                }
            }
        }
    }

    private var platformForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("A voice for each destination", "Enable the places you write. Add any website, app or mode.")
            HStack {
                Picker("Destination", selection: $selectedDestination) {
                    ForEach(draft.destinations) { item in
                        Text(item.name + (item.enabled ? " · On" : "")).tag(item.id)
                    }
                }.labelsHidden().accessibilityLabel("Destination")
                Button {
                    let item = WritingDestination(name: "New platform", target: "", style: draft.style)
                    draft.destinations.append(item); selectedDestination = item.id
                } label: { Image(systemName: "plus") }
                .help("Add a platform, app or mode").accessibilityLabel("Add destination")
                .disabled(draft.destinations.count >= 20)
            }
            if let index = draft.destinations.firstIndex(where: { $0.id == selectedDestination }) {
                destinationEditor(index)
            } else {
                Text("Add a destination to create its writing preferences.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func destinationEditor(_ index: Int) -> some View {
        let item = draft.destinations[index]
        Toggle("Use preferences for \(item.name)", isOn: $draft.destinations[index].enabled)
            .toggleStyle(.switch).controlSize(.small)
        if !WritingDestination.presets.contains(where: { $0.id == item.id }) {
            WritingField("Name") { TextField("Platform name", text: $draft.destinations[index].name) }
            WritingField("Match by") {
                Picker("Match by", selection: $draft.destinations[index].kind) {
                    ForEach(WritingDestinationKind.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
                .onChange(of: draft.destinations[index].kind) { _, kind in
                    draft.destinations[index].target = kind == .mode ? ContextMode.coding.rawValue : ""
                }
            }
            WritingField(item.kind == .mode ? "Mode" : "Destination") {
                if item.kind == .mode {
                    Picker("Mode", selection: $draft.destinations[index].target) {
                        ForEach(ContextMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden()
                } else {
                    TextField(item.kind == .website ? "example.com" : "App name or bundle identifier", text: $draft.destinations[index].target)
                }
            }
            Button("Remove destination", role: .destructive) {
                draft.destinations.remove(at: index)
                selectedDestination = draft.destinations.first?.id ?? ""
            }.font(.caption)
        } else {
            Label(item.target, systemImage: item.kind == .mode ? "slider.horizontal.3" : "globe")
                .font(.caption).foregroundStyle(.secondary)
        }
        if item.isX {
            Toggle("My account supports longer posts", isOn: $draft.destinations[index].longPosts)
                .toggleStyle(.switch).controlSize(.small)
            Text("\(item.effectiveCharacterBudget.formatted()) characters. Set this to match your X account; Voxen doesn’t check subscriptions.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            WritingField("Character budget") {
                TextField("0", value: $draft.destinations[index].characterBudget, format: .number.grouping(.never))
                    .frame(width: 90).accessibilityLabel("Character budget")
                Text("0 = adapt").font(.caption).foregroundStyle(.secondary)
            }
        }
        Text("Character budgets take priority over word targets. These guide the model, not a platform-side guarantee; links and emoji may count differently. Presets describe posts or captions, not every field.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Customize writing style", isOn: $draft.destinations[index].customStyle)
            .toggleStyle(.switch).controlSize(.small)
            .onChange(of: draft.destinations[index].customStyle) { _, custom in
                if custom, draft.destinations[index].style == WritingStyle() { draft.destinations[index].style = draft.style }
            }
        if item.customStyle {
            WritingStyleEditor(style: $draft.destinations[index].style)
        } else {
            Text("Uses your default voice from Style.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func sectionHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WritingStyleEditor: View {
    @Binding var style: WritingStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WritingField("Detail") {
                Picker("Detail", selection: $style.depth) {
                    ForEach(WritingDepth.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Detail")
            }
            Text(style.depth.guidance).font(.caption).foregroundStyle(.secondary)
            WritingField("Assumptions") {
                Picker("Assumptions", selection: $style.assumptions) {
                    ForEach(WritingAssumptions.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }
            Text(style.assumptions.guidance + " Proposals are never presented as existing features or personal facts.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            WritingField("Tone") {
                Picker("Tone", selection: $style.tone) { ForEach(WritingTone.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            WritingField("Format") {
                Picker("Format", selection: $style.format) { ForEach(WritingFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            WritingField("Emojis") {
                Picker("Emojis", selection: $style.emojis) { ForEach(WritingEmojis.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            WritingField("Hashtags") {
                Picker("Hashtags", selection: $style.hashtags) { ForEach(WritingHashtags.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            WritingField("Word target") {
                TextField("0", value: $style.targetWords, format: .number.grouping(.never)).frame(width: 90).accessibilityLabel("Word target")
                Text("0 = adapt · up to 1,500").font(.caption).foregroundStyle(.secondary)
            }
            WritingField("Output language") {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("English, Hindi, German…", text: $style.language)
                        .accessibilityLabel("Output language")
                    Text("Language of the generated text. Leave blank to follow your speech.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .help("A spoken or written language, not a programming language.")
            }
            WritingTextArea(title: "Extra preferences", hint: "E.g. short paragraphs, dry humour, no sales pitch. Up to 1,500 characters.", text: $style.instructions, height: 65)
        }
    }
}

private struct WritingField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.system(size: 13)).frame(width: 108, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }.textFieldStyle(.roundedBorder)
    }
}
private struct WritingTextArea: View {
    let title: String
    let hint: String
    @Binding var text: String
    var height: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(6).frame(height: height)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                .accessibilityLabel(title)
        }
    }
}
