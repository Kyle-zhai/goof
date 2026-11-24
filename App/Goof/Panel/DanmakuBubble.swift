import AppKit
import SwiftUI

/// Draws one scrolling danmaku ("name  message") into a bitmap. The scrolling
/// layer then only moves bitmaps, which Core Animation does on the render
/// server without waking the app every frame.
@MainActor
enum DanmakuBubble {
    static let horizontalPadding: CGFloat = 8
    static let nameGap: CGFloat = 6

    static func height(fontSize: CGFloat) -> CGFloat {
        ceil(fontSize + 9)
    }

    static func size(for message: ChatMessage, fontSize: CGFloat) -> CGSize {
        let text = attributed(message, fontSize: fontSize)
        return CGSize(width: ceil(text.size().width + horizontalPadding * 2), height: height(fontSize: fontSize))
    }

    static func attributed(_ message: ChatMessage, fontSize: CGFloat) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        let result = NSMutableAttributedString(string: message.displayName, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize - 1, weight: .semibold),
            .foregroundColor: NameColor.ns(for: message),
            .shadow: shadow,
            .kern: 0,
        ])
        if result.length > 0 {
            // The gap between name and message, as kerning on the name's last character.
            result.addAttribute(.kern, value: nameGap, range: NSRange(location: result.length - 1, length: 1))
        }
        result.append(NSAttributedString(string: message.body, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96),
            .shadow: shadow,
        ]))
        return result
    }

    /// The bubble at `scale` pixels per point.
    static func image(for message: ChatMessage, fontSize: CGFloat, scale: CGFloat) -> CGImage? {
        let size = size(for: message, fontSize: fontSize)
        let pixelsWide = Int(ceil(size.width * scale)), pixelsHigh = Int(ceil(size.height * scale))
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        draw(message, in: CGRect(origin: .zero, size: size), fontSize: fontSize)
        context.flushGraphics()
        return rep.cgImage
    }

    static func nsImage(for message: ChatMessage, fontSize: CGFloat, scale: CGFloat = 2) -> NSImage? {
        guard let cg = image(for: message, fontSize: fontSize, scale: scale) else { return nil }
        return NSImage(cgImage: cg, size: size(for: message, fontSize: fontSize))
    }

    private static func draw(_ message: ChatMessage, in bounds: CGRect, fontSize: CGFloat) {
        if message.isMine {
            // Your own messages get a coral outline so you can find them in the flow.
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                                    xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            NSColor(srgbRed: 1, green: 0.353, blue: 0.373, alpha: 0.16).setFill()
            path.fill()
            NSColor(srgbRed: 1, green: 0.47, blue: 0.49, alpha: 0.85).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let text = attributed(message, fontSize: fontSize)
        let textSize = text.size()
        text.draw(at: NSPoint(x: horizontalPadding, y: floor((bounds.height - textSize.height) / 2)))
    }
}
