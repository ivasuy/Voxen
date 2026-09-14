import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        VStack(spacing: 12) {
            permissionRow("Microphone", granted: permissions.microphone == .authorized,
                          action: permissions.requestMicrophone)
            permissionRow("Accessibility", granted: permissions.accessibility,
                          action: permissions.requestAccessibility)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Enable", action: action)
            }
        }
    }
}
