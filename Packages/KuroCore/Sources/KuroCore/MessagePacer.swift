import Foundation

/// Releases queued items one at a time so a burst of messages reads as a
/// steady stream instead of a jump. Used by the list ("stack") style.
public struct MessagePacer<Element: Sendable>: Sendable {
    /// Gap between releases when the backlog is small.
    public var interval: TimeInterval
    /// Shorter gap used once the backlog grows past `burstThreshold`.
    public var burstInterval: TimeInterval
    public var burstThreshold: Int
    /// Oldest items are dropped beyond this many, like a busy livestream.
    public var capacity: Int

    public private(set) var pending: [Element] = []
    private var lastRelease: Date = .distantPast

    public init(interval: TimeInterval = 0.35, burstInterval: TimeInterval = 0.12, burstThreshold: Int = 8, capacity: Int = 40) {
        self.interval = interval
        self.burstInterval = burstInterval
        self.burstThreshold = burstThreshold
        self.capacity = max(1, capacity)
    }

    public mutating func enqueue(_ element: Element) {
        pending.append(element)
        if pending.count > capacity { pending.removeFirst(pending.count - capacity) }
    }

    /// Returns the next item if enough time has passed since the last release.
    public mutating func release(at now: Date) -> Element? {
        guard !pending.isEmpty else { return nil }
        let gap = pending.count > burstThreshold ? burstInterval : interval
        guard now.timeIntervalSince(lastRelease) >= gap else { return nil }
        lastRelease = now
        return pending.removeFirst()
    }

    public mutating func removeAll(where shouldRemove: (Element) -> Bool) {
        pending.removeAll(where: shouldRemove)
    }

    public mutating func clear() {
        pending.removeAll()
    }
}
