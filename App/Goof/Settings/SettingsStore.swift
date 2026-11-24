import CoreGraphics
import Foundation
import GoofCore
import Observation

enum DanmakuStyle: String, CaseIterable, Identifiable, Sendable {
    /// Livestream danmaku flying right to left in lanes.
    case scroll
    /// A tidy list growing from the bottom, easier to read.
    case stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: "滚动弹幕"
        case .stack: "规整列表"
        }
    }

    var subtitle: String {
        switch self {
        case .scroll: "像直播一样从右往左飘过，热闹"
        case .stack: "一条条从下往上排，方便看清每句话"
        }
    }

    var symbol: String {
        switch self {
        case .scroll: "text.line.first.and.arrowtriangle.forward"
        case .stack: "list.bullet.rectangle"
        }
    }
}

enum DanmakuFontSize: String, CaseIterable, Identifiable, Sendable {
    case small, standard, large

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .small: 12
        case .standard: 13
        case .large: 15
        }
    }

    var title: String {
        switch self {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        }
    }
}

/// Per-device preferences, persisted in UserDefaults.
@Observable
@MainActor
final class SettingsStore {
    private let defaults: UserDefaults

    /// Catalog room ids the user allows.
    var allowedApps: Set<String> { didSet { defaults.set(Array(allowedApps).sorted(), forKey: Keys.allowed) } }
    var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Keys.idle) } }
    var postAnonymously: Bool { didSet { defaults.set(postAnonymously, forKey: Keys.anonymous) } }
    var panelEnabled: Bool { didSet { defaults.set(panelEnabled, forKey: Keys.panel) } }
    /// Nil when not paused; `.distantFuture` when paused until resumed.
    var pausedUntil: Date? { didSet { defaults.set(pausedUntil, forKey: Keys.pausedUntil) } }
    var danmakuStyle: DanmakuStyle { didSet { defaults.set(danmakuStyle.rawValue, forKey: Keys.style) } }
    var danmakuSpeed: Double { didSet { defaults.set(danmakuSpeed, forKey: Keys.speed) } }
    var fontSize: DanmakuFontSize { didSet { defaults.set(fontSize.rawValue, forKey: Keys.fontSize) } }
    /// Background strength of the floating panel, 0.35...0.9.
    var panelOpacity: Double { didSet { defaults.set(panelOpacity, forKey: Keys.opacity) } }
    var replayHistory: Bool { didSet { defaults.set(replayHistory, forKey: Keys.replay) } }
    var hideWhenSharing: Bool { didSet { defaults.set(hideWhenSharing, forKey: Keys.hideWhenSharing) } }
    var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: Keys.hotKey) } }
    var showCountInMenuBar: Bool { didSet { defaults.set(showCountInMenuBar, forKey: Keys.menuBarCount) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) } }
    var panelCollapsed: Bool { didSet { defaults.set(panelCollapsed, forKey: Keys.collapsed) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.idle: 2,
            Keys.anonymous: true,
            Keys.panel: true,
            Keys.style: DanmakuStyle.scroll.rawValue,
            Keys.speed: 90.0,
            Keys.fontSize: DanmakuFontSize.standard.rawValue,
            Keys.opacity: 0.62,
            Keys.replay: true,
            Keys.hideWhenSharing: true,
            Keys.hotKey: true,
            Keys.menuBarCount: true,
            Keys.onboarded: false,
        ])
        // Early builds stored bundle ids; map them to room ids.
        let stored = defaults.stringArray(forKey: Keys.allowed) ?? []
        allowedApps = Set(stored.compactMap { AppCatalog.app(id: $0)?.id ?? AppCatalog.app(forBundleID: $0)?.id })
        idleMinutes = defaults.integer(forKey: Keys.idle)
        postAnonymously = defaults.bool(forKey: Keys.anonymous)
        panelEnabled = defaults.bool(forKey: Keys.panel)
        pausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date
        danmakuStyle = DanmakuStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .scroll
        danmakuSpeed = defaults.double(forKey: Keys.speed)
        fontSize = DanmakuFontSize(rawValue: defaults.string(forKey: Keys.fontSize) ?? "") ?? .standard
        panelOpacity = defaults.double(forKey: Keys.opacity)
        replayHistory = defaults.bool(forKey: Keys.replay)
        hideWhenSharing = defaults.bool(forKey: Keys.hideWhenSharing)
        hotKeyEnabled = defaults.bool(forKey: Keys.hotKey)
        showCountInMenuBar = defaults.bool(forKey: Keys.menuBarCount)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        panelCollapsed = defaults.bool(forKey: Keys.collapsed)
    }

    var idleThreshold: TimeInterval { TimeInterval(max(1, idleMinutes) * 60) }

    private enum Keys {
        static let allowed = "allowedApps"
        static let idle = "idleThresholdMinutes"
        static let anonymous = "postAnonymously"
        static let panel = "panelEnabled"
        static let pausedUntil = "pausedUntil"
        static let style = "danmakuStyle"
        static let speed = "danmakuSpeed"
        static let fontSize = "danmakuFontSize"
        static let opacity = "panelOpacity"
        static let replay = "replayHistory"
        static let hideWhenSharing = "hideWhenSharing"
        static let hotKey = "hotKeyEnabled"
        static let menuBarCount = "showCountInMenuBar"
        static let onboarded = "hasCompletedOnboarding"
        static let collapsed = "panelCollapsed"
    }
}
