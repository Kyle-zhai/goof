import AppKit
import QuartzCore
import SwiftUI

/// The scrolling danmaku. Each message is a pre-rendered bitmap moved by a
/// Core Animation animation, so a busy room costs almost no CPU. `DanmakuFeed`
/// decides lanes and timing; this view only mirrors its items.
struct DanmakuScrollLayer: NSViewRepresentable {
    let items: [DanmakuItem]
    let fontSize: CGFloat
    let laneHeight: CGFloat
    let paused: Bool
    let menu: (ChatMessage) -> NSMenu

    func makeNSView(context: Context) -> DanmakuScrollNSView {
        DanmakuScrollNSView(frame: .zero)
    }

    func updateNSView(_ view: DanmakuScrollNSView, context: Context) {
        view.menuProvider = menu
        view.update(items: items, fontSize: fontSize, laneHeight: laneHeight, paused: paused)
    }
}

final class DanmakuScrollNSView: NSView {
    var menuProvider: ((ChatMessage) -> NSMenu)?

    private struct Entry {
        var item: DanmakuItem
        let layer: CALayer
    }

    private var entries: [UUID: Entry] = [:]
    private var fontSize: CGFloat = 13
    private var laneHeight: CGFloat = 24
    private var paused = false
    private var laidOutWidth: CGFloat = 0
    private static let animationKey = "scroll"

    /// Holds the bubbles; its mask softens the left and right edges.
    private let contentLayer = CALayer()
    private let edgeMask = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        edgeMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        contentLayer.mask = edgeMask
        layer?.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(items: [DanmakuItem], fontSize: CGFloat, laneHeight: CGFloat, paused: Bool) {
        let now = Date()
        let restyled = fontSize != self.fontSize || laneHeight != self.laneHeight
        self.fontSize = fontSize
        self.laneHeight = laneHeight

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if restyled { removeAll() }

        let wanted = Set(items.map(\.id))
        for (id, entry) in entries where !wanted.contains(id) {
            entry.layer.removeFromSuperlayer()
            entries[id] = nil
        }

        let pauseChanged = paused != self.paused
        self.paused = paused

        for item in items {
            if var entry = entries[item.id] {
                let restarted = entry.item.start != item.start
                entry.item = item
                entries[item.id] = entry
                if pauseChanged || restarted { apply(entry, at: now) }
            } else if let layer = makeLayer(for: item.message) {
                let entry = Entry(item: item, layer: layer)
                entries[item.id] = entry
                contentLayer.addSublayer(layer)
                position(entry)
                apply(entry, at: now)
            }
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = bounds
        edgeMask.frame = contentLayer.bounds
        let fade = bounds.width > 0 ? Double(min(0.2, DanmakuEdgeFade.width / bounds.width)) : 0
        edgeMask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        let widthChanged = bounds.width != laidOutWidth
        laidOutWidth = bounds.width
        let now = Date()
        for entry in entries.values {
            position(entry)
            // The first update can arrive before the view has a size, and the
            // panel can be resized mid-flight: retarget from the current time.
            if widthChanged { apply(entry, at: now) }
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moved to a display with a different scale: redraw the bitmaps.
        let scale = backingScale
        for entry in entries.values {
            entry.layer.contentsScale = scale
            entry.layer.contents = DanmakuBubble.image(for: entry.item.message, fontSize: fontSize, scale: scale)
        }
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func makeLayer(for message: ChatMessage) -> CALayer? {
        let scale = backingScale
        guard let image = DanmakuBubble.image(for: message, fontSize: fontSize, scale: scale) else { return nil }
        let size = DanmakuBubble.size(for: message, fontSize: fontSize)
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.opacity = message.isReplay ? 0.5 : 1
        return layer
    }

    /// Lanes count from the top; the view is not flipped, so y counts from the bottom.
    private func position(_ entry: Entry) {
        let height = entry.layer.bounds.height
        let laneTop = 4 + CGFloat(entry.item.lane) * laneHeight + (laneHeight - height) / 2
        entry.layer.position.y = bounds.height - laneTop - height
    }

    /// Starts (or freezes) the layer at the position its timing implies right now.
    private func apply(_ entry: Entry, at now: Date) {
        let layer = entry.layer
        let item = entry.item
        let width = bounds.width
        let elapsed = max(0, now.timeIntervalSince(item.start))
        let progress = min(1, elapsed / max(item.duration, 0.01))
        let currentX = width - CGFloat(progress) * (width + CGFloat(item.width))
        let endX = -CGFloat(item.width)

        layer.removeAnimation(forKey: Self.animationKey)
        if paused {
            layer.position.x = currentX
            return
        }
        let remaining = item.duration - elapsed
        guard remaining > 0 else {
            layer.position.x = endX
            return
        }
        layer.position.x = endX
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = currentX
        animation.toValue = endX
        animation.duration = remaining
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: Self.animationKey)
    }

    private func removeAll() {
        entries.values.forEach { $0.layer.removeFromSuperlayer() }
        entries = [:]
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        // The danmaku area doubles as a handle for moving the panel.
        window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let hit = entries.values.first { entry in
            let frame = entry.layer.presentation()?.frame ?? entry.layer.frame
            return frame.insetBy(dx: -2, dy: -2).contains(point)
        }
        guard let message = hit?.item.message else { return nil }
        return menuProvider?(message)
    }
}

/// A frozen frame of the scrolling style drawn with SwiftUI, used for
/// screenshots (Core Animation layers do not show up in offscreen renders).
struct FrozenDanmakuLayer: View {
    let items: [DanmakuItem]
    let fontSize: CGFloat
    let laneHeight: CGFloat
    let now: Date
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    if let image = DanmakuBubble.nsImage(for: item.message, fontSize: fontSize, scale: displayScale) {
                        let width = Double(proxy.size.width)
                        let progress = min(1, max(0, now.timeIntervalSince(item.start) / item.duration))
                        let x = width - progress * (width + item.width)
                        let height = DanmakuBubble.height(fontSize: fontSize)
                        let y = 4 + CGFloat(item.lane) * laneHeight + (laneHeight - height) / 2
                        Image(nsImage: image)
                            .opacity(item.message.isReplay ? 0.5 : 1)
                            .offset(x: CGFloat(x), y: y)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .mask {
                let fade = proxy.size.width > 0 ? min(0.2, DanmakuEdgeFade.width / proxy.size.width) : 0
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: fade),
                                       .init(color: .black, location: 1 - fade), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipped()
    }
}

/// How far danmaku fade in at the right edge and out at the left edge.
enum DanmakuEdgeFade {
    static let width: CGFloat = 14
}

/// The right-click menu for a message, shared by both styles' AppKit paths.
@MainActor
enum MessageMenu {
    static func make(for message: ChatMessage, model: AppModel) -> NSMenu {
        let menu = NSMenu()
        if !message.isMine {
            let report = NSMenuItem(title: "举报", action: nil, keyEquivalent: "")
            let reasons = NSMenu()
            for reason in ReportReason.allCases {
                reasons.addItem(ClosureMenuItem(title: reason.title) { model.report(message, reason: reason) })
            }
            report.submenu = reasons
            menu.addItem(report)
            menu.addItem(ClosureMenuItem(title: "屏蔽「\(message.displayName)」") { model.block(message) })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: "复制") { model.copy(message) })
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
