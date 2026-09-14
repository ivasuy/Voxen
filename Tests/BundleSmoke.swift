import AppKit

let path = FileManager.default.currentDirectoryPath + "/build/Voxen.app"
guard let bundle = Bundle(path: path), bundle.bundleIdentifier == "dev.voiceintent.router",
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Voxen",
      let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
      let resources = bundle.resourceURL,
      NSImage(contentsOf: resources.appendingPathComponent(iconName)) != nil,
      NSImage(contentsOf: resources.appendingPathComponent("voxen-logo-v1.png")) != nil else {
    fatalError("App identity or icon resources invalid")
}
let image = NSWorkspace.shared.icon(forFile: path)
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not read Finder icon") }
try png.write(to: URL(fileURLWithPath: "build/finder-icon-readback.png"))
print("PASS: Voxen bundle identity and icons; Finder icon readback saved")
