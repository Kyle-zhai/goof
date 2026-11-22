import Foundation

/// Assigns incoming danmaku to horizontal lanes so they never overlap.
///
/// All items move right-to-left at the same speed, so an item can enter a
/// lane once the previous item's tail has fully entered the panel plus a gap.
/// When every lane is busy the item waits in a short queue; if the queue is
/// full the oldest waiting item is dropped, like a busy livestream.
public struct DanmakuLayout: Sendable {
    public struct Placement: Sendable, Equatable {
        public let lane: Int
        public let startTime: Date
        /// Seconds from entering at the right edge to fully leaving at the left edge.
        public let duration: TimeInterval
    }

    public var laneCount: Int { didSet { resizeLanes() } }
    public var panelWidth: Double
    /// Points per second.
    public var speed: Double
    /// Minimum horizontal gap between two items in the same lane, in points.
    public var gap: Double

    private var laneFreeAt: [Date]

    public init(laneCount: Int = 4, panelWidth: Double = 320, speed: Double = 90, gap: Double = 24) {
        self.laneCount = max(1, laneCount)
        self.panelWidth = panelWidth
        self.speed = speed
        self.gap = gap
        self.laneFreeAt = Array(repeating: .distantPast, count: max(1, laneCount))
    }

    /// Duration an item of `width` stays on screen.
    public func duration(forWidth width: Double) -> TimeInterval {
        (panelWidth + width) / speed
    }

    /// Returns a placement if a lane is free at `now`, otherwise nil.
    /// Lowest free lane wins so messages read top-down.
    public mutating func place(width: Double, at now: Date) -> Placement? {
        guard let lane = laneFreeAt.firstIndex(where: { $0 <= now }) else { return nil }
        laneFreeAt[lane] = now.addingTimeInterval((width + gap) / speed)
        return Placement(lane: lane, startTime: now, duration: duration(forWidth: width))
    }

    /// Shifts every lane's availability later, used when scrolling is paused
    /// (for example while the pointer hovers over the danmaku).
    public mutating func delay(by seconds: TimeInterval) {
        guard seconds > 0 else { return }
        laneFreeAt = laneFreeAt.map { $0 == .distantPast ? $0 : $0.addingTimeInterval(seconds) }
    }

    /// Forgets every placement, for example after switching rooms.
    public mutating func reset() {
        laneFreeAt = Array(repeating: .distantPast, count: laneCount)
    }

    /// The earliest time any lane becomes free.
    public var nextFreeTime: Date { laneFreeAt.min() ?? .distantPast }

    private mutating func resizeLanes() {
        laneCount = max(1, laneCount)
        if laneFreeAt.count < laneCount {
            laneFreeAt += Array(repeating: .distantPast, count: laneCount - laneFreeAt.count)
        } else if laneFreeAt.count > laneCount {
            laneFreeAt.removeLast(laneFreeAt.count - laneCount)
        }
    }
}
