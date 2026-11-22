import Foundation

/// An app that can have a room.
public struct CatalogApp: Sendable, Hashable, Identifiable, Codable {
    public enum Category: String, Sendable, Codable, CaseIterable {
        case ai = "AI"
        case code = "开发"
        case design = "设计"
        case productivity = "效率"
        case creative = "创作"
    }

    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let category: Category

    public init(bundleID: String, name: String, category: Category) {
        self.bundleID = bundleID
        self.name = name
        self.category = category
    }
}

public enum AppCatalog {
    /// Curated, non-sensitive work apps. All of them start disabled; the user
    /// opts in per app from the dashboard. Browsers, messaging apps, finance,
    /// health and similar apps are intentionally absent.
    public static let defaultApps: [CatalogApp] = [
        .init(bundleID: "com.anthropic.claudefordesktop", name: "Claude", category: .ai),
        .init(bundleID: "com.openai.chat", name: "ChatGPT", category: .ai),
        .init(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", category: .code),
        .init(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", category: .code),
        .init(bundleID: "com.apple.dt.Xcode", name: "Xcode", category: .code),
        .init(bundleID: "dev.zed.Zed", name: "Zed", category: .code),
        .init(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA", category: .code),
        .init(bundleID: "com.figma.Desktop", name: "Figma", category: .design),
        .init(bundleID: "com.bohemiancoding.sketch3", name: "Sketch", category: .design),
        .init(bundleID: "notion.id", name: "Notion", category: .productivity),
        .init(bundleID: "com.linear", name: "Linear", category: .productivity),
        .init(bundleID: "md.obsidian", name: "Obsidian", category: .productivity),
        .init(bundleID: "com.apple.logic10", name: "Logic Pro", category: .creative),
        .init(bundleID: "com.apple.FinalCut", name: "Final Cut Pro", category: .creative),
        .init(bundleID: "org.blenderfoundation.blender", name: "Blender", category: .creative),
    ]

    /// Bundle id of Kuro itself. Keep in sync with `project.yml`.
    public static let kuroBundleID = "app.kuro.Kuro"

    /// Becoming frontmost never counts as leaving the current app.
    public static let ignoredBundleIDs: Set<String> = [
        kuroBundleID,
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
        "com.apple.UserNotificationCenter",
    ]

    public static func app(for bundleID: String) -> CatalogApp? {
        defaultApps.first { $0.bundleID == bundleID }
    }
}
