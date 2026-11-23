import AppKit
import CoreGraphics
import GoofCore

/// Feeds real macOS signals into `RoomResolver`:
/// - the frontmost app, from NSWorkspace activation notifications (no permission needed)
/// - idle time, from CGEventSource (no permission needed; it reads only a timestamp)
/// - lock, sleep, screensaver and fast user switching
///
/// Apps outside the catalog are reported to the resolver as "some other app";
/// their bundle ids are never stored or sent anywhere.
@MainActor
final class ActivityMonitor {
    private(set) var resolver: RoomResolver
    /// The catalog app in front, allowed or not. Nil for any other app. Kept in
    /// memory only, so the menu can offer "turn on Figma" while you use Figma.
    private(set) var frontmostCatalogID: String?
    var onStatusChange: ((RoomResolver.Status) -> Void)?
    /// The frontmost catalog app or the pending room changed.
    var onSignalsChange: (() -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var awayReasons: Set<String> = [] {
        didSet {
            guard awayReasons.isEmpty != oldValue.isEmpty else { return }
            apply { $0.sessionAwayChanged(!awayReasons.isEmpty, at: Date()) }
        }
    }

    init(allowed: Set<String>, idleThreshold: TimeInterval) {
        resolver = RoomResolver(config: .init(idleThreshold: idleThreshold), allowed: allowed)
    }

    var pendingRoom: (roomID: String, since: Date)? { resolver.pendingRoom }

    func graceRemaining(at now: Date = Date()) -> TimeInterval? {
        resolver.graceRemaining(at: now)
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostChanged(app?.bundleIdentifier)
        }
        awayWhile(workspace, start: NSWorkspace.willSleepNotification, end: NSWorkspace.didWakeNotification, reason: "sleep")
        awayWhile(workspace, start: NSWorkspace.screensDidSleepNotification, end: NSWorkspace.screensDidWakeNotification, reason: "display")
        awayWhile(workspace, start: NSWorkspace.sessionDidResignActiveNotification, end: NSWorkspace.sessionDidBecomeActiveNotification, reason: "session")

        let distributed = DistributedNotificationCenter.default()
        awayWhile(distributed, start: .init("com.apple.screenIsLocked"), end: .init("com.apple.screenIsUnlocked"), reason: "locked")
        awayWhile(distributed, start: .init("com.apple.screensaver.didstart"), end: .init("com.apple.screensaver.didstop"), reason: "screensaver")

        frontmostChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        timer?.invalidate()
        timer = nil
    }

    func setAllowed(_ ids: Set<String>) {
        apply { $0.setAllowed(ids, at: Date()) }
    }

    func setIdleThreshold(_ seconds: TimeInterval) {
        resolver.config.idleThreshold = seconds
        tick()
    }

    // MARK: -

    private func frontmostChanged(_ bundleID: String?) {
        switch AppCatalog.classify(bundleID: bundleID, ownBundleID: ownBundleID) {
        case .ignored:
            return
        case .app(let app):
            frontmostCatalogID = app.id
            apply { $0.frontmostChanged(to: app.id, at: Date()) }
        case .other:
            frontmostCatalogID = nil
            apply { $0.frontmostChanged(to: nil, at: Date()) }
        }
        onSignalsChange?()
    }

    private func tick() {
        let idle = Self.secondsSinceLastInput()
        apply { $0.idleUpdated(idle, at: Date()) }
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType (~0) is not bridged as an enum case.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func apply(_ change: (inout RoomResolver) -> RoomResolver.Status) {
        let before = resolver.status
        let pendingBefore = resolver.pendingRoom?.roomID
        let after = change(&resolver)
        if after != before { onStatusChange?(after) }
        if resolver.pendingRoom?.roomID != pendingBefore { onSignalsChange?() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(note) }
        }
        observers.append((center, token))
    }

    private func awayWhile(_ center: NotificationCenter, start: Notification.Name, end: Notification.Name, reason: String) {
        observe(center, start) { [weak self] _ in self?.awayReasons.insert(reason) }
        observe(center, end) { [weak self] _ in self?.awayReasons.remove(reason) }
    }
}
