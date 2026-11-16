import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: n * 0.055, y: n * 0.055, width: n * 0.89, height: n * 0.89), xRadius: n * 0.20, yRadius: n * 0.20)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.29, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.10, alpha: 1))!
        gradient.draw(in: tile, angle: -90)
        if let symbol = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
            symbol.draw(in: NSRect(x: n * 0.20, y: n * 0.24, width: n * 0.60, height: n * 0.51))
        }
        NSColor(calibratedRed: 0.45, green: 0.90, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.38, y: n * 0.17, width: n * 0.24, height: n * 0.035), xRadius: n * 0.017, yRadius: n * 0.017).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
