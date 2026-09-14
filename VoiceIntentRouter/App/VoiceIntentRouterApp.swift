import SwiftUI
import AppKit

@main
struct VoiceIntentRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkey = GlobalHotkeyManager()
    private lazy var state = AppState()
    private let overlay = FloatingOverlayController()
    private let isBrowserContextProbe = ProcessInfo.processInfo.arguments.contains("--probe-browser-context")
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if isBrowserContextProbe {
            Task { @MainActor in
                await BrowserCaptureProbe.run()
                NSApp.terminate(nil)
            }
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voxen")
        item.button?.toolTip = "Voxen"
        statusItem = item
        state.onChange = { [weak self] in
            guard let self else { return }
            self.refreshMenu()
            self.overlay.update(state: self.state)
        }
        state.openSettings = { [weak self] in self?.openSettingsPage() }
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.state.toggle() } }
        state.settings.applyShortcut = { [weak self] shortcut in
            guard let self else { return }
            guard !self.state.phase.isBusy else { throw RouterError.message("Finish the current voice request before changing settings.") }
            try self.hotkey.register(shortcut)
        }
        do { try hotkey.register(state.settings.shortcut) }
        catch { state.report(error) }
        refreshMenu()
        // Opening the app should always give visible feedback, even after setup.
        // Defer activation until AppKit has completed launching the accessory app.
        DispatchQueue.main.async { [weak self] in self?.showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func refreshMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let modes = NSMenu()
        let auto = modes.addItem(withTitle: "Auto", action: #selector(setMode(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = "auto"
        auto.state = state.settings.modeOverride == nil ? .on : .off
        auto.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        for mode in ContextMode.allCases {
            let item = modes.addItem(withTitle: mode.label, action: #selector(setMode(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            item.target = self
            item.representedObject = mode.rawValue
            item.state = state.settings.modeOverride == mode ? .on : .off
        }
        let modeItem = menu.addItem(withTitle: "Mode", action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        modeItem.submenu = modes
        modeItem.isEnabled = !state.phase.isBusy
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettingsPage), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard !state.phase.isBusy else { return }
        state.settings.modeOverride = (sender.representedObject as? String).flatMap(ContextMode.init(rawValue:))
        refreshMenu()
    }

    @objc private func openSettingsPage() {
        state.navigation.page = .settings
        showSettings()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Voxen"
            let content = NSHostingView(rootView: LiveCommandCenter(state: state, onSave: { [weak self] in self?.refreshMenu() }))
            window.contentView = content
            window.contentMinSize = NSSize(width: 740, height: 580)
            window.setContentSize(NSSize(width: 780, height: 640))
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if !isBrowserContextProbe { state.shutDown() }
    }
}
