import AppKit
import Observation

/// The livestream-style "account card" people see next to named messages.
struct LocalProfile: Codable, Equatable, Sendable {
    var username: String
    var displayName: String
    var bio: String
    var accentHex: String

    static let empty = LocalProfile(username: "", displayName: "", bio: "", accentHex: "#FF5A5F")

    static let maxDisplayName = 24
    static let maxBio = 80

    /// Mirrors what a backend should enforce. Nil when valid.
    var validationError: String? {
        // An empty nickname is allowed: it means "always anonymous".
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > Self.maxDisplayName { return "昵称最多 \(Self.maxDisplayName) 个字" }
        if name.hasPrefix("匿名") { return "昵称不能以「匿名」开头，免得和匿名弹幕混淆" }
        if !username.isEmpty, username.range(of: #"^[A-Za-z0-9_一-鿿]{2,20}$"#, options: .regularExpression) == nil {
            return "用户名需为 2–20 位字母、数字、下划线或中文"
        }
        if bio.count > Self.maxBio { return "简介最多 \(Self.maxBio) 个字" }
        return nil
    }

    var trimmed: LocalProfile {
        LocalProfile(username: username.trimmingCharacters(in: .whitespaces),
                     displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                     bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                     accentHex: accentHex)
    }
}

/// Stores the profile on this Mac. A backend receives it as a `PublicProfile`.
@Observable
@MainActor
final class ProfileStore {
    private(set) var profile: LocalProfile
    private(set) var avatar: NSImage?

    private let defaults: UserDefaults
    private let avatarURL: URL

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Kuro", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        avatarURL = base.appendingPathComponent("avatar.png")

        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(LocalProfile.self, from: data) {
            profile = saved
        } else {
            profile = .empty
        }
        avatar = NSImage(contentsOf: avatarURL)
    }

    var hasNickname: Bool { !profile.displayName.isEmpty }

    var publicProfile: PublicProfile {
        PublicProfile(username: profile.username, displayName: profile.displayName, bio: profile.bio,
                      accentHex: profile.accentHex, avatarPNG: try? Data(contentsOf: avatarURL))
    }

    func save(_ newValue: LocalProfile) {
        profile = newValue.trimmed
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.key) }
    }

    /// Crops the picked image to a centered square and stores a 256×256 PNG.
    func setAvatar(from url: URL) throws {
        guard let image = NSImage(contentsOf: url), let png = Self.squarePNG(from: image, side: 256) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try png.write(to: avatarURL, options: .atomic)
        avatar = NSImage(data: png)
    }

    func removeAvatar() {
        try? FileManager.default.removeItem(at: avatarURL)
        avatar = nil
    }

    static func squarePNG(from image: NSImage, side: Int) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height), edge = min(width, height)
        let crop = CGRect(x: (width - edge) / 2, y: (height - edge) / 2, width: edge, height: edge).integral
        guard let square = cg.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    private static let key = "localProfile"
}
