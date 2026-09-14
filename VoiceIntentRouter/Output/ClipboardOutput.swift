import AppKit
import os

/// Copies plain text only. Never posts keyboard events or restores old content.
@MainActor
protocol GeneratedTextWriting {
    func copy(_ generated: GeneratedText) throws
}

@MainActor
final class ClipboardOutput: GeneratedTextWriting {
    private let clipboard: ClipboardManager
    private let log = Logger(subsystem: "dev.voiceintent.router", category: "Clipboard")

    init(pasteboard: NSPasteboard = .general) { clipboard = ClipboardManager(pasteboard: pasteboard) }

    nonisolated static func clean(_ text: String) -> String {
        let withoutANSI = text.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
                                                     with: "", options: .regularExpression)
        let normalized = withoutANSI.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let safe = normalized.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t"
        }.map(String.init).joined()
        // Remove decorative terminal rulers, but preserve code, paragraphs, and normal punctuation.
        return safe.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.count >= 8 && trimmed.allSatisfy { "─━—-=*_ ".contains($0) })
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func copy(_ generated: GeneratedText) throws {
        let result = Self.clean(generated.text)
        guard !result.isEmpty else { throw RouterError.message("The model returned no usable text.") }
        try clipboard.write(result)
        log.info("Generated text copied")
    }
}
