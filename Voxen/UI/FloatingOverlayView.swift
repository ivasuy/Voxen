import SwiftUI
import AppKit

struct FloatingOverlayView: View {
    @ObservedObject var state: AppState
    var body: some View {
        OverlayContent(phase: state.phase, audioLevel: state.audioLevel, detail: state.detail)
    }
}

/// Value-only presentation also allows previews without reading credentials or recording audio.
struct OverlayContent: View {
    let phase: RouterPhase
    let audioLevel: Float
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { phase == .error ? Color(red: 1, green: 0.69, blue: 0.46) : VoxenStyle.mint }
    private var title: String {
        switch phase {
        case .transcribing, .transforming: return "Writing"
        case .done: return "Copied"
        case .error: return "Error"
        default: return phase.rawValue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            indicator.frame(width: 24, height: 20)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
        }
        .padding(.horizontal, 17)
        .frame(height: 38)
        .background(VoxenStyle.charcoal, in: Capsule())
        .overlay(Capsule().strokeBorder(VoxenStyle.ink.opacity(0.13), lineWidth: 0.5))
        .foregroundStyle(VoxenStyle.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(phase == .error ? detail : "")
        .padding(8)
    }

    @ViewBuilder private var indicator: some View {
        if phase == .listening {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let profile = 0.3 + 0.7 * abs(sin(Double(index + 1) * 0.82))
                    Capsule().fill(accent)
                        .frame(width: 2.5, height: 18)
                        .scaleEffect(x: 1, y: 0.15 + 0.85 * Double(min(max(audioLevel, 0), 1)) * profile)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: audioLevel)
            .accessibilityElement(children: .ignore).accessibilityLabel("Microphone listening")
        } else if phase == .transcribing || phase == .transforming {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        } else {
            Image(systemName: phase == .done ? "checkmark" : phase == .error ? "exclamationmark" : "waveform")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
        }
    }
}

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingOverlayController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func update(state: AppState) {
        dismissTask?.cancel()
        if state.phase == .idle { panel?.orderOut(nil); return }
        if panel == nil {
            let panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 54),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: FloatingOverlayView(state: state))
            self.panel = panel
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let frame = screen?.visibleFrame, let panel {
            let size = panel.contentView?.fittingSize ?? NSSize(width: 160, height: 54)
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 46,
                                  width: size.width, height: size.height), display: true)
        }
        panel?.orderFrontRegardless()
        if state.phase == .done || state.phase == .error {
            let delay: Duration = state.phase == .error ? .seconds(12) : .seconds(2)
            dismissTask = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                self?.panel?.orderOut(nil)
            }
        }
    }
}
