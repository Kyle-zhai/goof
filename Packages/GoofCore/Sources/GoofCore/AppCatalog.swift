import Foundation

/// An app that has a room. Rooms are keyed by a stable slug (`id`), not by
/// bundle id, so editions of the same app (stable / beta / community) share
/// one room and a backend never has to know about bundle ids.
public struct CatalogApp: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, CaseIterable, Identifiable {
        case ai, code, design, office, creative

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .ai: "AI"
            case .code: "开发"
            case .design: "设计"
            case .office: "办公"
            case .creative: "创作"
            }
        }
    }

    /// Stable room id. Also stored in user settings, so never rename or reuse one.
    public let id: String
    public let name: String
    public let category: Category
    /// Every bundle id that counts as this app.
    public let bundleIDs: [String]
    /// Tile color (hex) used when the app is not installed and its icon is unavailable.
    public let tint: String

    public init(id: String, name: String, category: Category, bundleIDs: [String], tint: String) {
        self.id = id
        self.name = name
        self.category = category
        self.bundleIDs = bundleIDs
        self.tint = tint
    }
}

public enum AppCatalog {
    /// Curated, non-sensitive work apps. Every entry starts disabled; people opt in
    /// per app. Browsers, messaging, mail, finance, health and dating apps are
    /// intentionally absent: being seen in those rooms would say too much.
    ///
    /// To add an app, append an entry with a new `id` (see CONTRIBUTING.md).
    public static let apps: [CatalogApp] = [
        // AI
        .init(id: "claude", name: "Claude", category: .ai, bundleIDs: ["com.anthropic.claudefordesktop"], tint: "#D97757"),
        .init(id: "chatgpt", name: "ChatGPT", category: .ai, bundleIDs: ["com.openai.chat"], tint: "#10A37F"),

        // Code
        .init(id: "vscode", name: "Visual Studio Code", category: .code, bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], tint: "#1E88E5"),
        .init(id: "cursor", name: "Cursor", category: .code, bundleIDs: ["com.todesktop.230313mzl4w4u92"], tint: "#26262B"),
        .init(id: "windsurf", name: "Windsurf", category: .code, bundleIDs: ["com.exafunction.windsurf"], tint: "#0E9F8E"),
        .init(id: "xcode", name: "Xcode", category: .code, bundleIDs: ["com.apple.dt.Xcode"], tint: "#1C7CF4"),
        .init(id: "zed", name: "Zed", category: .code, bundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"], tint: "#2F6FEB"),
        .init(id: "intellij", name: "IntelliJ IDEA", category: .code, bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], tint: "#FE315D"),
        .init(id: "pycharm", name: "PyCharm", category: .code, bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], tint: "#21D789"),
        .init(id: "webstorm", name: "WebStorm", category: .code, bundleIDs: ["com.jetbrains.WebStorm"], tint: "#07C3F2"),
        .init(id: "goland", name: "GoLand", category: .code, bundleIDs: ["com.jetbrains.goland"], tint: "#3D7BF7"),
        .init(id: "android-studio", name: "Android Studio", category: .code, bundleIDs: ["com.google.android.studio"], tint: "#3DDC84"),
        .init(id: "terminal", name: "终端", category: .code, bundleIDs: ["com.apple.Terminal"], tint: "#2B2B2B"),
        .init(id: "iterm2", name: "iTerm2", category: .code, bundleIDs: ["com.googlecode.iterm2"], tint: "#1D1F21"),
        .init(id: "warp", name: "Warp", category: .code, bundleIDs: ["dev.warp.Warp-Stable"], tint: "#01A4FF"),
        .init(id: "ghostty", name: "Ghostty", category: .code, bundleIDs: ["com.mitchellh.ghostty"], tint: "#3551F3"),

        // Design
        .init(id: "figma", name: "Figma", category: .design, bundleIDs: ["com.figma.Desktop"], tint: "#A259FF"),
        .init(id: "sketch", name: "Sketch", category: .design, bundleIDs: ["com.bohemiancoding.sketch3"], tint: "#F7B500"),
        .init(id: "photoshop", name: "Photoshop", category: .design, bundleIDs: ["com.adobe.Photoshop"], tint: "#31A8FF"),
        .init(id: "illustrator", name: "Illustrator", category: .design, bundleIDs: ["com.adobe.illustrator"], tint: "#FF9A00"),
        .init(id: "affinity-designer", name: "Affinity Designer", category: .design, bundleIDs: ["com.seriflabs.affinitydesigner2"], tint: "#134881"),

        // Office
        .init(id: "notion", name: "Notion", category: .office, bundleIDs: ["notion.id"], tint: "#2F2F2F"),
        .init(id: "obsidian", name: "Obsidian", category: .office, bundleIDs: ["md.obsidian"], tint: "#7C3AED"),
        .init(id: "linear", name: "Linear", category: .office, bundleIDs: ["com.linear"], tint: "#5E6AD2"),
        .init(id: "word", name: "Word", category: .office, bundleIDs: ["com.microsoft.Word"], tint: "#2B579A"),
        .init(id: "excel", name: "Excel", category: .office, bundleIDs: ["com.microsoft.Excel"], tint: "#217346"),
        .init(id: "powerpoint", name: "PowerPoint", category: .office, bundleIDs: ["com.microsoft.Powerpoint"], tint: "#D24726"),
        .init(id: "keynote", name: "Keynote", category: .office, bundleIDs: ["com.apple.iWork.Keynote"], tint: "#2D7CF6"),
        .init(id: "pages", name: "Pages", category: .office, bundleIDs: ["com.apple.iWork.Pages"], tint: "#F79A2B"),
        .init(id: "numbers", name: "Numbers", category: .office, bundleIDs: ["com.apple.iWork.Numbers"], tint: "#34B24A"),
        .init(id: "wps", name: "WPS Office", category: .office, bundleIDs: ["com.kingsoft.wpsoffice.mac"], tint: "#E5383B"),

        // Creative
        .init(id: "final-cut", name: "Final Cut Pro", category: .creative, bundleIDs: ["com.apple.FinalCut"], tint: "#4A4A4A"),
        .init(id: "logic", name: "Logic Pro", category: .creative, bundleIDs: ["com.apple.logic10"], tint: "#3A3A3C"),
        .init(id: "davinci", name: "DaVinci Resolve", category: .creative, bundleIDs: ["com.blackmagic-design.DaVinciResolve"], tint: "#E04E39"),
        .init(id: "blender", name: "Blender", category: .creative, bundleIDs: ["org.blenderfoundation.blender"], tint: "#EA7600"),
        .init(id: "ableton", name: "Ableton Live", category: .creative, bundleIDs: ["com.ableton.live"], tint: "#111111"),
    ]

    /// Bundle id of Goof itself. Keep in sync with `project.yml`.
    public static let goofBundleID = "app.goof.Goof"

    /// Becoming frontmost never counts as leaving the app you were using:
    /// Goof's own windows, the Dock, Spotlight, Control Center and similar system UI.
    public static let ignoredBundleIDs: Set<String> = [
        goofBundleID,
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
        "com.apple.UserNotificationCenter",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
    ]

    /// What the frontmost app means for room detection.
    public enum Frontmost: Sendable, Equatable {
        /// Goof or system UI: keep whatever room the user is in.
        case ignored
        /// An app from the catalog (allowed or not; the resolver decides).
        case app(CatalogApp)
        /// Any other app. Nothing about it is recorded or sent anywhere.
        case other
    }

    public static func classify(bundleID: String?, ownBundleID: String? = nil) -> Frontmost {
        guard let bundleID else { return .other }
        if bundleID == ownBundleID || ignoredBundleIDs.contains(bundleID) { return .ignored }
        if let app = app(forBundleID: bundleID) { return .app(app) }
        return .other
    }

    public static func app(id: String) -> CatalogApp? {
        byID[id]
    }

    public static func app(forBundleID bundleID: String) -> CatalogApp? {
        byBundleID[bundleID]
    }

    private static let byID: [String: CatalogApp] =
        Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static let byBundleID: [String: CatalogApp] =
        Dictionary(apps.flatMap { app in app.bundleIDs.map { ($0, app) } }, uniquingKeysWith: { first, _ in first })
}
