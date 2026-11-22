import AppKit
import KuroCore
import Observation

struct DanmakuItem: Identifiable, Equatable {
    let id: UUID
    let message: ChatMessage
    let lane: Int
    let start: Date
    let duration: TimeInterval
    let width: Double
}

/// Turns a stream of messages into positioned, non-overlapping danmaku.
@Observable
@MainActor
final class DanmakuFeed {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let laneHeight: Double = 24
    static let horizontalPadding: Double = 20

    private(set) var items: [DanmakuItem] = []
    var speed: Double = 90 { didSet { layout.speed = speed } }

    @ObservationIgnored private var layout = DanmakuLayout()
    @ObservationIgnored private var queue: [ChatMessage] = []
    @ObservationIgnored private var timer: Timer?
    private let maxQueue = 30

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    func resize(width: Double, height: Double) {
        layout.panelWidth = max(100, width)
        layout.laneCount = max(1, Int(height / Self.laneHeight))
    }

    func push(_ message: ChatMessage) {
        guard !items.contains(where: { $0.id == message.id }),
              !queue.contains(where: { $0.id == message.id }) else { return }
        queue.append(message)
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        step()
    }

    /// Replay history quickly on join, newest last.
    func replay(_ messages: [ChatMessage]) {
        queue = Array(messages.suffix(maxQueue))
        step()
    }

    func remove(messageID: UUID) {
        items.removeAll { $0.message.id == messageID }
        queue.removeAll { $0.id == messageID }
    }

    func removeAll(where predicate: (ChatMessage) -> Bool) {
        items.removeAll { predicate($0.message) }
        queue.removeAll(where: predicate)
    }

    func clear() {
        items = []
        queue = []
    }

    static func width(of message: ChatMessage) -> Double {
        let name = NSAttributedString(string: message.displayName + "  ", attributes: [.font: nameFont]).size().width
        let body = NSAttributedString(string: message.body, attributes: [.font: font]).size().width
        return ceil(name + body + horizontalPadding)
    }

    private func step() {
        let now = Date()
        items.removeAll { now.timeIntervalSince($0.start) > $0.duration }
        while let next = queue.first {
            let width = Self.width(of: next)
            guard let placement = layout.place(width: width, at: now) else { break }
            queue.removeFirst()
            items.append(DanmakuItem(id: next.id, message: next, lane: placement.lane, start: placement.startTime, duration: placement.duration, width: width))
        }
    }
}
