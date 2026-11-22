import AppKit
import CoreGraphics
import KuroCore

/// Feeds real macOS signals into `RoomResolver`:
/// - frontmost app via NSWorkspace activation notifications (no permission needed)
/// - idle time via CGEventSource (no permission needed, reads only a timestamp)
/// - lock / sleep / screensaver / fast user switching
@MainActor
final class ActivityMonitor {
    private(set) var resolver: RoomResolver
    var onStatusChange: ((RoomResolver.Status) -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var awayReasons: Set<String> = [] {
        didSet { apply { $0.sessionAwayChanged(!awayReasons.isEmpty, at: Date()) } }
    }

    init(allowed: Set<String>, idleThreshold: TimeInterval) {
        resolver = RoomResolver(config: .init(idleThreshold: idleThreshold), allowed: allowed)
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.apply { $0.frontmostChanged(to: app?.bundleIdentifier, at: Date()) }
        }
        awayWhile(ws, start: NSWorkspace.willSleepNotification, end: NSWorkspace.didWakeNotification, reason: "sleep")
        awayWhile(ws, start: NSWorkspace.screensDidSleepNotification, end: NSWorkspace.screensDidWakeNotification, reason: "display")
        awayWhile(ws, start: NSWorkspace.sessionDidResignActiveNotification, end: NSWorkspace.sessionDidBecomeActiveNotification, reason: "session")

        let dnc = DistributedNotificationCenter.default()
        awayWhile(dnc, start: .init("com.apple.screenIsLocked"), end: .init("com.apple.screenIsUnlocked"), reason: "locked")
        awayWhile(dnc, start: .init("com.apple.screensaver.didstart"), end: .init("com.apple.screensaver.didstop"), reason: "screensaver")

        apply { $0.frontmostChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, at: Date()) }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.3
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

    private func tick() {
        let idle = Self.secondsSinceLastInput()
        apply { $0.idleUpdated(idle, at: Date()) }
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType (~0) is not bridged as a case.
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private func apply(_ change: (inout RoomResolver) -> RoomResolver.Status) {
        let before = resolver.status
        let after = change(&resolver)
        if after != before { onStatusChange?(after) }
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
