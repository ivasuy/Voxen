// Scoped local-build restart. Never terminates another installation or unrelated process.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let current = root.appendingPathComponent("build/Voxen.app")
let previous = root.appendingPathComponent("build/Voice Intent Router.app")
let targets = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == "dev.voiceintent.router" &&
        ($0.bundleURL?.standardizedFileURL == current || $0.bundleURL?.standardizedFileURL == previous)
}
for app in targets { app.terminate() }
let deadline = Date().addingTimeInterval(5)
while targets.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
guard targets.allSatisfy(\.isTerminated) else {
    print("Quit the current Voxen voice request before relaunching.")
    exit(1)
}
let archive = root.appendingPathComponent("build/PreviousBuilds/Voice Intent Router.app")
if FileManager.default.fileExists(atPath: previous.path), !FileManager.default.fileExists(atPath: archive.path) {
    try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: previous, to: archive)
    print("Previous app preserved in build/PreviousBuilds.")
}
var completed = false
var launchFailed = false
NSWorkspace.shared.openApplication(at: current, configuration: NSWorkspace.OpenConfiguration()) { app, error in
    launchFailed = app == nil || error != nil
    completed = true
}
let launchDeadline = Date().addingTimeInterval(10)
while !completed && Date() < launchDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
guard completed && !launchFailed else { print("Could not launch Voxen.app."); exit(1) }
print("PASS: Voxen.app launched")
