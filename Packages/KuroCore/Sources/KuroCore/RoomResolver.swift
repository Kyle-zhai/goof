import Foundation

/// Decides which room (if any) the user is in, from three raw signals:
/// the frontmost app, how long the user has been idle, and whether the
/// session is away (screen locked / asleep / switched user).
///
/// Pure value type with no AppKit dependency so it can be unit tested by
/// feeding it events and timestamps. The app calls `tick(at:)` about once a
/// second so that debounce and grace timers can expire.
public struct RoomResolver: Sendable {
    public struct Config: Sendable, Equatable {
        /// A newly frontmost app must stay frontmost this long before we join its room.
        public var debounce: TimeInterval
        /// After leaving, keep the room (shown as "away") this long before exiting.
        public var grace: TimeInterval
        /// No keyboard/mouse input for this long means the user is not really "using" the app.
        public var idleThreshold: TimeInterval

        public init(debounce: TimeInterval = 3, grace: TimeInterval = 45, idleThreshold: TimeInterval = 120) {
            self.debounce = debounce
            self.grace = grace
            self.idleThreshold = idleThreshold
        }
    }

    public enum Status: Sendable, Equatable {
        /// Not in any room.
        case none
        /// In the room and actively using the app.
        case active(roomID: String)
        /// Still in the room (grace period) but not currently using the app.
        case away(roomID: String)

        public var roomID: String? {
            switch self {
            case .none: return nil
            case .active(let id), .away(let id): return id
            }
        }
    }

    public var config: Config
    /// Bundle ids the user has allowed. Anything else never produces a room.
    public private(set) var allowed: Set<String>
    /// Bundle ids that never count as "switching away" (Kuro itself, Dock, Spotlight...).
    public let ignored: Set<String>

    public private(set) var status: Status = .none

    private var frontmost: String?
    private var idleSeconds: TimeInterval = 0
    private var sessionAway = false
    private var candidate: (roomID: String, since: Date)?
    private var leftAt: Date?

    public init(config: Config = Config(), allowed: Set<String>, ignored: Set<String> = AppCatalog.ignoredBundleIDs) {
        self.config = config
        self.allowed = allowed
        self.ignored = ignored
    }

    // MARK: Inputs

    @discardableResult
    public mutating func frontmostChanged(to bundleID: String?, at now: Date) -> Status {
        if let bundleID, ignored.contains(bundleID) { return status }
        frontmost = bundleID
        return evaluate(at: now)
    }

    @discardableResult
    public mutating func idleUpdated(_ seconds: TimeInterval, at now: Date) -> Status {
        idleSeconds = max(0, seconds)
        return evaluate(at: now)
    }

    @discardableResult
    public mutating func sessionAwayChanged(_ away: Bool, at now: Date) -> Status {
        sessionAway = away
        return evaluate(at: now)
    }

    @discardableResult
    public mutating func setAllowed(_ ids: Set<String>, at now: Date) -> Status {
        allowed = ids
        // Revoking permission for the current room exits immediately; no grace.
        if let room = status.roomID, !ids.contains(room) {
            status = .none
            leftAt = nil
        }
        return evaluate(at: now)
    }

    @discardableResult
    public mutating func tick(at now: Date) -> Status {
        evaluate(at: now)
    }

    // MARK: Logic

    /// The room the user would be in right now if there were no timers.
    private var desiredRoom: String? {
        guard !sessionAway, idleSeconds < config.idleThreshold,
              let frontmost, allowed.contains(frontmost) else { return nil }
        return frontmost
    }

    private mutating func evaluate(at now: Date) -> Status {
        // Locked screen / sleep: leave right away so online counts stay honest.
        if sessionAway {
            candidate = nil
            leftAt = nil
            status = .none
            return status
        }

        let desired = desiredRoom
        if desired != candidate?.roomID {
            candidate = desired.map { ($0, now) }
        }

        let current = status.roomID

        // Back in (or still in) the current room: no debounce needed.
        if let desired, desired == current {
            status = .active(roomID: desired)
            leftAt = nil
            return status
        }

        // A different room has been stable long enough: switch to it.
        if let desired, let candidate, now.timeIntervalSince(candidate.since) >= config.debounce {
            status = .active(roomID: desired)
            leftAt = nil
            return status
        }

        // Not using the current room's app: hold it during the grace period.
        if let current {
            let left = leftAt ?? now
            leftAt = left
            if now.timeIntervalSince(left) >= config.grace {
                status = .none
                leftAt = nil
            } else {
                status = .away(roomID: current)
            }
        }
        return status
    }
}
