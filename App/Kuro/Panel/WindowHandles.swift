import AppKit
import SwiftUI

/// Lets the user move the borderless panel by dragging this area. A press that
/// does not move counts as a click.
struct WindowDragArea: NSViewRepresentable {
    var toolTip: String?
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        view.toolTip = toolTip
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onClick = onClick
        view.toolTip = toolTip
    }

    final class DragView: NSView {
        var onClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = NSEvent.mouseLocation
            let origin = window.frame.origin
            var dragged = false
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let point = NSEvent.mouseLocation
                let dx = point.x - start.x, dy = point.y - start.y
                if !dragged, abs(dx) + abs(dy) > 3 { dragged = true }
                if dragged { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
            }
            if dragged {
                window.saveFrame(usingName: window.frameAutosaveName)
            } else {
                onClick?()
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

/// A corner grip that resizes the panel, keeping its top-left corner in place.
struct WindowResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ view: GripView, context: Context) {}

    final class GripView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = NSEvent.mouseLocation
            let frame = window.frame
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let point = NSEvent.mouseLocation
                let width = max(window.minSize.width, frame.width + (point.x - start.x))
                let height = max(window.minSize.height, frame.height - (point.y - start.y))
                window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
            }
            window.saveFrame(usingName: window.frameAutosaveName)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.28).setStroke()
            for offset in stride(from: CGFloat(3), through: 9, by: 3) {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
                path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
}

/// Reports when the pointer enters or leaves this area, even while another app
/// is active (the panel never activates Kuro). Tracking areas work by geometry,
/// so this can sit behind SwiftUI content without blocking clicks on it.
struct HoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { onHover?(false) }
        }

        // Never the target of clicks: only the tracking area matters.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
