import AppKit

@MainActor
final class ClipboardManager {
    private let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func write(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw RouterError.message("Could not copy the generated text to the clipboard.")
        }
    }
}
