import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        guard let nsColor = NSColor(hex: hex) else { return nil }
        self.init(nsColor: nsColor)
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        NSColor(self).hexString
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? .systemPink
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func darker(_ fraction: CGFloat = 0.25) -> NSColor {
        blended(withFraction: fraction, of: .black) ?? self
    }
}

enum KuroColors {
    /// The brand coral used for the logo, accents and "mine" highlights.
    static let accent = Color(red: 1.0, green: 0.353, blue: 0.373)
    static let accentHex = "#FF5A5F"

    /// Preset name colors offered in the profile.
    static let presets = ["#FF5A5F", "#FF9F1C", "#2EC4B6", "#3A86FF", "#8338EC", "#E36FD0", "#30343F"]

    /// A readable name color for someone who did not pick one.
    static func nameColor(for key: String) -> Color {
        let palette = ["#FF8A93", "#FFB86B", "#6FD3FF", "#8EE3A3", "#C9A2FF", "#FF9FD0", "#F6D36B", "#7FE0D2"]
        return Color(hex: palette[Int(StableHash.fnv1a(key) % UInt64(palette.count))]) ?? .white
    }
}

enum NameColor {
    /// The color of an author's name in the danmaku. Author-picked colors are
    /// lightened so that even a dark pick stays readable on the dark panel.
    static func ns(for message: ChatMessage) -> NSColor {
        if message.isAnonymous { return NSColor.white.withAlphaComponent(0.62) }
        if let hex = message.accentHex, let color = NSColor(hex: hex) {
            return color.blended(withFraction: 0.42, of: .white) ?? color
        }
        return NSColor(KuroColors.nameColor(for: message.authorKey))
    }

    static func color(for message: ChatMessage) -> Color {
        Color(nsColor: ns(for: message))
    }
}
