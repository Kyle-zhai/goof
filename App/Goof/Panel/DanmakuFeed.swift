import AppKit
import GoofCore
import Observation
import SwiftUI

struct DanmakuItem: Identifiable, Equatable {
    let id: UUID
    let message: ChatMessage
    let lane: Int
    var start: Date
    let duration: TimeInterval
    let width: Double
}

/// Turns the room's message stream into what the panel shows, in either style:
/// non-overlapping scrolling lanes, or a paced list that grows from the bottom.
@Observable
@MainActor
final class DanmakuFeed {
    private(set) var style: DanmakuStyle = .scroll
    private(set) var fontSize: DanmakuFontSize = .standard
    /// Scrolling style: items currently crossing the panel.
    private(set) var items: [DanmakuItem] = []
    /// List style: rows currently in the list, oldest first.
    private(set) var rows: [ChatMessage] = []
    /// Non-nil while scrolling is frozen (pointer over the danmaku).
    private(set) var pausedAt: Date?

    @ObservationIgnored private var layout = DanmakuLayout()
    private var queue: [ChatMessage] = []
    private var pacer = MessagePacer<ChatMessage>()
    @ObservationIgnored private var timer: Timer?
    private let usesTimer: Bool
    private let maxQueue = 30
    private let maxRows = 60

    /// - Parameter startsTimer: false for snapshots and tests, which drive the feed by hand.
    init(startsTimer: Bool = true) {
        usesTimer = startsTimer
    }

    var laneHeight: Double { Double(fontSize.points) + 11 }
    var isPaused: Bool { pausedAt != nil }
    /// Messages waiting to appear, for the "paused" hint.
    var waitingCount: Int { queue.count + pacer.pending.count }
    var isEmpty: Bool { items.isEmpty && rows.isEmpty }

    /// The clock the scrolling view should use: frozen while paused.
    func clock(_ date: Date) -> Date { pausedAt ?? date }

    // MARK: Configuration

    func setStyle(_ newStyle: DanmakuStyle) {
        guard newStyle != style else { return }
        // Keep what is still waiting; what is on screen does not carry over.
        let waiting = queue + pacer.pending
        clearAll()
        style = newStyle
        waiting.forEach(enqueue)
        step()
    }

    func setSpeed(_ speed: Double) {
        layout.speed = max(30, speed)
    }

    func setFontSize(_ size: DanmakuFontSize) {
        guard size != fontSize else { return }
        fontSize = size
        items = []
        layout.reset()
    }

    func resize(width: Double, height: Double) {
        guard width.isFinite, height.isFinite else { return }
        layout.panelWidth = max(120, width)
        layout.laneCount = lanes(forHeight: height)
    }

    private func lanes(forHeight height: Double) -> Int {
        guard height.isFinite, height > 8 else { return 1 }
        return max(1, Int((height - 8) / laneHeight))
    }

    // MARK: Content

    func push(_ message: ChatMessage) {
        guard !contains(message.id) else { return }
        enqueue(message)
        step()
    }

    /// History shown on join, oldest first.
    func replay(_ messages: [ChatMessage]) {
        messages.suffix(maxQueue).forEach(enqueue)
        step()
    }

    /// Replaces a message in place (for example an optimistic send) or adds it.
    func upsert(_ message: ChatMessage) {
        if let index = rows.firstIndex(where: { $0.id == message.id }) {
            rows[index] = message
        } else if !items.contains(where: { $0.id == message.id }) {
            push(message)
        }
    }

    /// Marks a message the user wrote that arrived from the server before
    /// `send` returned (a broadcast echo), wherever it is in the feed.
    func markMine(messageID: UUID) {
        func mark(_ message: inout ChatMessage) {
            if message.id == messageID { message.isMine = true }
        }
        for index in rows.indices { mark(&rows[index]) }
        for index in queue.indices { mark(&queue[index]) }
        pacer.modify(mark)
        for index in items.indices where items[index].id == messageID {
            var message = items[index].message
            message.isMine = true
            let item = items[index]
            items[index] = DanmakuItem(id: item.id, message: message, lane: item.lane, start: item.start,
                                       duration: item.duration, width: item.width)
        }
    }

    func contains(messageID: UUID) -> Bool {
        contains(messageID)
    }

    func remove(messageID: UUID) {
        removeAll { $0.id == messageID }
    }

    func removeAll(where shouldRemove: (ChatMessage) -> Bool) {
        items.removeAll { shouldRemove($0.message) }
        rows.removeAll(where: shouldRemove)
        queue.removeAll(where: shouldRemove)
        pacer.removeAll(where: shouldRemove)
    }

    func clear() {
        clearAll()
    }

    // MARK: Hover

    /// The pointer is over the danmaku: freeze it so people can read and right-click.
    /// Scrolling items stop where they are; the list holds new rows until the pointer leaves.
    func setHovering(_ hovering: Bool) {
        if hovering, pausedAt == nil {
            pausedAt = Date()
        } else if !hovering, let pausedAt {
            let pause = Date().timeIntervalSince(pausedAt)
            for index in items.indices { items[index].start.addTimeInterval(pause) }
            layout.delay(by: pause)
            self.pausedAt = nil
            ensureTimer()
            step()
        }
    }

    // MARK: Measuring

    func width(of message: ChatMessage) -> Double {
        Double(DanmakuBubble.size(for: message, fontSize: fontSize.points).width)
    }

    // MARK: Snapshots

    /// Lays out a frozen, deterministic frame for screenshots: the messages go
    /// through the real lane layout as if they had just arrived one by one.
    func freezeForSnapshot(_ messages: [ChatMessage], panelWidth: Double, height: Double) {
        clearAll()
        resize(width: panelWidth, height: height)
        switch style {
        case .scroll:
            // Irregular gaps between arrivals, like a real room.
            let gaps: [TimeInterval] = [0.5, 0.35, 0.6, 0.3, 0.55, 0.4, 0.65, 0.35, 0.5, 0.45]
            var clock = Date()
            var placed: [DanmakuItem] = []
            for (index, message) in messages.enumerated() {
                let width = self.width(of: message)
                var placement = layout.place(width: width, at: clock)
                var waits = 0
                while placement == nil, waits < 100 {
                    clock.addTimeInterval(0.1)
                    waits += 1
                    placement = layout.place(width: width, at: clock)
                }
                guard let placement else { continue }
                placed.append(DanmakuItem(id: message.id, message: message, lane: placement.lane,
                                          start: placement.startTime, duration: placement.duration, width: width))
                clock.addTimeInterval(gaps[index % gaps.count])
            }
            let now = clock.addingTimeInterval(0.4)
            items = placed.filter { now.timeIntervalSince($0.start) < $0.duration }
            pausedAt = now
        case .stack:
            rows = Array(messages.suffix(maxRows))
        }
    }

    // MARK: - Private

    private func contains(_ id: UUID) -> Bool {
        items.contains { $0.id == id } || rows.contains { $0.id == id }
            || queue.contains { $0.id == id } || pacer.pending.contains { $0.id == id }
    }

    private func enqueue(_ message: ChatMessage) {
        switch style {
        case .scroll:
            queue.append(message)
            if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        case .stack:
            pacer.enqueue(message)
        }
        ensureTimer()
    }

    /// The feed only ticks while something is moving or waiting, so an idle
    /// panel costs no wakeups.
    private func ensureTimer() {
        guard usesTimer, timer == nil, pausedAt == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func clearAll() {
        items = []
        rows = []
        queue = []
        pacer.clear()
        layout.reset()
        pausedAt = nil
        stopTimer()
    }

    private func step() {
        guard pausedAt == nil else { return stopTimer() }
        defer { if items.isEmpty, queue.isEmpty, pacer.pending.isEmpty { stopTimer() } }
        let now = Date()
        switch style {
        case .scroll:
            if items.contains(where: { now.timeIntervalSince($0.start) > $0.duration }) {
                items.removeAll { now.timeIntervalSince($0.start) > $0.duration }
            }
            while let next = queue.first {
                let width = self.width(of: next)
                guard let placement = layout.place(width: width, at: now) else { break }
                queue.removeFirst()
                items.append(DanmakuItem(id: next.id, message: next, lane: placement.lane, start: placement.startTime,
                                         duration: placement.duration, width: width))
            }
        case .stack:
            if let next = pacer.release(at: now) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    rows.append(next)
                    if rows.count > maxRows { rows.removeFirst(rows.count - maxRows) }
                }
            }
        }
    }
}
