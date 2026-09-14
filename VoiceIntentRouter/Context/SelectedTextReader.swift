import ApplicationServices
import Foundation

struct SelectedTextReader {
    // Injectable Accessibility boundary for tests; no whole-field value or clipboard fallback.
    var attribute: (AXUIElement, String) -> CFTypeRef? = { element, name in
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    var stringForRange: (AXUIElement, CFRange) -> String? = { element, selection in
        AXUIElementSetMessagingTimeout(element, 0.05)
        var range = selection
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                        value, &result) == .success else { return nil }
        return result as? String
    }
    var stringForMarkerRange: (AXUIElement, CFTypeRef) -> String? = { element, marker in
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        // Chromium/WebKit expose selections spanning multiple DOM text nodes as opaque text markers.
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString,
                                                        marker, &result) == .success else { return nil }
        return result as? String
    }

    /// Called only at the explicit voice trigger. Walk ancestors, never page children or other windows.
    func read(processIdentifier: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(processIdentifier)
        guard let focused = Self.element(attribute(app, kAXFocusedUIElementAttribute)) else { return nil }
        return read(focused: focused)
    }

    func read(focused: AXUIElement) -> String? {
        let deadline = Date().addingTimeInterval(0.35)
        func get(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard Date() < deadline else { return nil }
            return attribute(element, name)
        }
        var current: AXUIElement? = focused
        for _ in 0..<16 {
            guard let element = current, Date() < deadline else { return nil }
            if get(element, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
            if let selected = get(element, kAXSelectedTextAttribute) as? String,
               let text = Self.usableSelection(selected) { return text }

            if let marker = get(element, "AXSelectedTextMarkerRange"), Date() < deadline,
               let selected = stringForMarkerRange(element, marker), let text = Self.usableSelection(selected) { return text }

            // Some controls expose only a selection range. Request that substring, not their entire value.
            if let value = get(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                let axValue = unsafeBitCast(value, to: AXValue.self)
                var raw = CFRange()
                if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &raw),
                   let range = Self.boundedRange(raw), Date() < deadline,
                   let selected = stringForRange(element, range), let text = Self.usableSelection(selected) { return text }
            }
            let role = get(element, kAXRoleAttribute) as? String
            if role == kAXWindowRole || role == kAXApplicationRole { return nil }
            current = Self.element(get(element, kAXParentAttribute))
        }
        return nil
    }

    static func usableSelection(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(text.prefix(12_000))
    }

    static func boundedRange(_ range: CFRange) -> CFRange? {
        guard range.location >= 0, range.length > 0, range.length <= Int.max - range.location else { return nil }
        return CFRange(location: range.location, length: min(range.length, 12_000))
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}
