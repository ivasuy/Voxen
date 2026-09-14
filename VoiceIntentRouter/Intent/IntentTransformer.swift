import Foundation
import os

/// Only this file can create clipboard-eligible text, after a successful model response.
struct GeneratedText {
    let text: String
    fileprivate init(_ text: String) { self.text = text }
}

struct IntentTransformer {
    let provider: any LLMProvider
    private let log = Logger(subsystem: "dev.voiceintent.router", category: "Intent")

    func transform(_ context: VoiceContext) async throws -> GeneratedText {
        guard !context.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RouterError.message("No transcript was returned.")
        }
        let selection = context.selectedText.flatMap { SelectedTextReader.usableSelection($0) }
        var payload: [String: Any] = [
            "APPLICATION": context.appName,
            "BUNDLE_IDENTIFIER": context.bundleIdentifier ?? "unknown",
            "CONTEXT_MODE": context.mode.rawValue,
            "WEBSITE_HOST": context.website?.host ?? "",
            "MODE_SOURCE": context.modeIsOverride ? "manual_override" : "application_hint",
            "SELECTION_STATUS": selection == nil ? "unavailable" : "included",
            "CURRENT_SELECTED_CONTEXT": selection ?? "",
            "SPOKEN_INTENT": context.transcript
        ]
        if let preferences = context.writingPreferences {
            payload["WRITING_PREFERENCES"] = preferences.payload(for: context)
            if preferences.profile.enabled { payload["WRITER_PROFILE"] = preferences.profile.payload }
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        log.info("Transformation requested; mode=\(context.mode.rawValue, privacy: .public); selection=\(context.selectedText != nil)")
        let output = try await provider.generate(
            instructions: PromptTemplates.instructions(for: context.mode, hasSelection: selection != nil,
                                                        modeIsOverride: context.modeIsOverride)
                + (context.writingPreferences?.instructions(for: context) ?? ""),
            input: String(decoding: data, as: UTF8.self))
        try Task.checkCancellation()
        let result = ClipboardOutput.clean(output)
        guard !result.isEmpty else { throw RouterError.message("The model returned empty text.") }
        return GeneratedText(result)
    }

    @discardableResult
    func transformAndCopy(_ context: VoiceContext, to clipboard: any GeneratedTextWriting) async throws -> GeneratedText {
        let generated = try await transform(context)
        try Task.checkCancellation()
        try await clipboard.copy(generated)
        return generated
    }
}
