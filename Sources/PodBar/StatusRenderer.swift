import AppKit

enum StatusRenderer {
    static func image(left: Int?, right: Int?) -> NSImage {
        // Keep the font unchanged; fit the wider row with one point of breathing room per side.
        let style: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let leftText = left.map { "\($0)%" } ?? "--"
        let rightText = right.map { "\($0)%" } ?? "--"
        let leftWidth = (leftText as NSString).size(withAttributes: style).width
        let rightWidth = (rightText as NSString).size(withAttributes: style).width
        let imageWidth = ceil(max(leftWidth, rightWidth)) + 2
        let image = NSImage(size: NSSize(width: imageWidth, height: 22), flipped: false) { _ in
            (leftText as NSString).draw(at: NSPoint(x: imageWidth - 1 - leftWidth, y: 11), withAttributes: style)
            (rightText as NSString).draw(at: NSPoint(x: imageWidth - 1 - rightWidth, y: 0), withAttributes: style)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AirPods 左右耳电量"
        return image
    }
}
