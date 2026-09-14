// Run separately from CoreTests: this opens/reopens only the built app.
// Reads window metadata, not screen pixels, text fields, or API credentials.
import AppKit
import CoreGraphics

let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let bundleID = "dev.voiceintent.router"

func waitUntil(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
}

func hasVisibleWindow(_ app: NSRunningApplication) -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains {
        $0[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier &&
        $0[kCGWindowLayer as String] as? Int == 0
    }
}

func openApp() -> NSRunningApplication {
    var result: NSRunningApplication?
    var failure: Error?
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
        result = app
        failure = error
    }
    guard waitUntil({ result != nil || failure != nil }), let result,
          result.bundleIdentifier == bundleID else {
        fatalError("Application launch failed: \(String(describing: failure))")
    }
    return result
}

let app = openApp()
guard waitUntil({ hasVisibleWindow(app) }) else { fatalError("Launch did not show a visible settings window") }
print("PASS: opening the app shows an on-screen window")
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let settingsWindow = windows.first {
    $0[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
}
if let bounds = settingsWindow?[kCGWindowBounds as String] as? [String: Double],
   let width = bounds["Width"], let height = bounds["Height"] {
    guard width >= 740, width <= 820, height >= 580, height <= 720 else { fatalError("Unexpected command center size: \(width) × \(height)") }
    print("PASS: compact settings window (\(Int(width)) × \(Int(height)))")
} else { fatalError("Could not verify settings window dimensions") }
let reopened = openApp()
guard reopened.processIdentifier == app.processIdentifier else { fatalError("Reopen unexpectedly launched a different instance") }
guard waitUntil({ hasVisibleWindow(reopened) }) else { fatalError("Reopen did not restore the settings window") }
print("PASS: reopening the running app leaves its settings window on screen")
