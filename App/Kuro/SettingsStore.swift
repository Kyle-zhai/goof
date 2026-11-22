import Foundation
import KuroCore
import Observation

/// Local, per-device preferences. The profile lives on the server.
@Observable
@MainActor
final class SettingsStore {
    private let defaults: UserDefaults

    var allowedApps: Set<String> { didSet { defaults.set(Array(allowedApps), forKey: Keys.allowed) } }
    var idleThresholdMinutes: Int { didSet { defaults.set(idleThresholdMinutes, forKey: Keys.idle) } }
    var postAnonymously: Bool { didSet { defaults.set(postAnonymously, forKey: Keys.anonymous) } }
    var panelEnabled: Bool { didSet { defaults.set(panelEnabled, forKey: Keys.panel) } }
    var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }
    var danmakuSpeed: Double { didSet { defaults.set(danmakuSpeed, forKey: Keys.speed) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.idle: 2,
            Keys.anonymous: true,
            Keys.panel: true,
            Keys.paused: false,
            Keys.speed: 90.0,
            Keys.onboarded: false,
        ])
        allowedApps = Set(defaults.stringArray(forKey: Keys.allowed) ?? [])
        idleThresholdMinutes = defaults.integer(forKey: Keys.idle)
        postAnonymously = defaults.bool(forKey: Keys.anonymous)
        panelEnabled = defaults.bool(forKey: Keys.panel)
        paused = defaults.bool(forKey: Keys.paused)
        danmakuSpeed = defaults.double(forKey: Keys.speed)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
    }

    /// What the resolver should consider: nothing while paused.
    var effectiveAllowedApps: Set<String> { paused ? [] : allowedApps }

    private enum Keys {
        static let allowed = "allowedApps"
        static let idle = "idleThresholdMinutes"
        static let anonymous = "postAnonymously"
        static let panel = "panelEnabled"
        static let paused = "paused"
        static let speed = "danmakuSpeed"
        static let onboarded = "hasCompletedOnboarding"
    }
}
