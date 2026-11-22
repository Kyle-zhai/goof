import AppKit
import KuroCore
import SwiftUI

/// Finds installed copies of catalog apps and their icons, with a small cache.
@MainActor
enum AppIconCache {
    private static var urls: [String: URL?] = [:]
    private static var icons: [String: NSImage] = [:]

    static func url(for app: CatalogApp) -> URL? {
        if let cached = urls[app.id] { return cached }
        let url = app.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        urls[app.id] = url
        return url
    }

    static func isInstalled(_ app: CatalogApp) -> Bool {
        url(for: app) != nil
    }

    static func icon(for app: CatalogApp) -> NSImage? {
        if let cached = icons[app.id] { return cached }
        guard let url = url(for: app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[app.id] = icon
        return icon
    }

    /// Call when the dashboard opens, in case apps were installed or removed.
    static func refresh() {
        urls = [:]
        icons = [:]
    }
}

/// The app's real icon when installed, otherwise a tinted tile with its initials.
struct AppTile: View {
    let app: CatalogApp?
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let app, let icon = AppIconCache.icon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                let tint = NSColor(hex: app?.tint ?? "#8A8F9D") ?? .gray
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(nsColor: tint), Color(nsColor: tint.darker(0.3))],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Text(Self.initials(app?.name ?? "?"))
                            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count > 1 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(name.prefix(1)).uppercased()
    }
}

/// Kuro's mark: two speech bubbles on a coral squircle.
struct KuroLogo: View {
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.54, blue: 0.48), Color(red: 0.89, green: 0.21, blue: 0.29)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.89, green: 0.21, blue: 0.29).opacity(0.3), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Round avatar: the picked image, or the first letter of the name on the accent color.
struct AvatarView: View {
    let image: NSImage?
    let name: String
    let accent: Color
    var size: CGFloat = 32
    var ring: CGFloat = 0

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "K").uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { if ring > 0 { Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: ring) } }
        .accessibilityHidden(true)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
