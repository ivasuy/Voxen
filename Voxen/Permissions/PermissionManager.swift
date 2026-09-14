import AppKit
import AVFoundation
import ApplicationServices

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var accessibility = AXIsProcessTrusted()
    var isReady: Bool { microphone == .authorized }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibility = AXIsProcessTrusted()
    }

    func requestMicrophone() {
        if microphone == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        } else { openPrivacy("Microphone") }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
        refresh()
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
