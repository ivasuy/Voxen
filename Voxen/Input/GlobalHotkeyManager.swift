import Carbon
import Foundation
import os

struct VoiceShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let standard = VoiceShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let modifierChoices: [(label: String, value: UInt32)] = [
        ("⌥", UInt32(optionKey)), ("⌃⌥", UInt32(controlKey | optionKey)),
        ("⇧⌘", UInt32(shiftKey | cmdKey)), ("⌃⇧", UInt32(controlKey | shiftKey))
    ]
    static let keyChoices: [(label: String, value: UInt32)] = [
        ("Space", 49), ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14),
        ("F", 3), ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40),
        ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12),
        ("R", 15), ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7), ("Y", 16), ("Z", 6)
    ]
    var isValid: Bool {
        Self.modifierChoices.contains { $0.value == modifiers } && Self.keyChoices.contains { $0.value == keyCode }
    }
    var label: String {
        (Self.modifierChoices.first { $0.value == modifiers }?.label ?? "") + " " +
        (Self.keyChoices.first { $0.value == keyCode }?.label ?? "?")
    }
}

final class GlobalHotkeyManager {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registeredShortcut: VoiceShortcut?
    var onPress: (() -> Void)?

    func register(_ shortcut: VoiceShortcut = .standard) throws {
        guard shortcut.isValid else { throw HotkeyError.invalid }
        guard registeredShortcut != shortcut else { return }
        if handler == nil {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x56495254, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Logger(subsystem: "dev.voiceintent.router", category: "Hotkey").info("Global shortcut received")
            manager.onPress?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { throw HotkeyError.registration(result) }
        }
        // Keep the old binding alive until its replacement has been accepted.
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: 0x56495254, id: 1),
                                         GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { throw HotkeyError.registration(status) }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = replacement
        registeredShortcut = shortcut
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

enum HotkeyError: LocalizedError {
    case registration(OSStatus)
    case invalid
    var errorDescription: String? { "That shortcut is unavailable. Choose another combination; your previous shortcut is unchanged." }
}
