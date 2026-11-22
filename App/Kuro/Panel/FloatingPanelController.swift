import AppKit
import SwiftUI

/// A borderless, non-activating, always-on-top panel. Non-activating is the
/// important part: typing in it does not make Kuro the frontmost app, so the
/// user stays in the room of the app they are actually using.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    // Borderless windows refuse key status by default; we need it for the text field.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController {
    static let expandedSize = NSSize(width: 340, height: 210)
    static let collapsedSize = NSSize(width: 190, height: 36)
    static let minExpandedSize = NSSize(width: 260, height: 150)

    private let panel: FloatingPanel
    private var expandedFrame: NSRect?

    init(model: AppModel) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - Self.expandedSize.width - 24, y: screen.minY + 120)
        panel = FloatingPanel(contentRect: NSRect(origin: origin, size: Self.expandedSize))
        panel.minSize = Self.minExpandedSize
        panel.setFrameAutosaveName("KuroFloatingPanel")
        let host = NSHostingView(rootView: PanelView().environment(model))
        host.sizingOptions = []
        panel.contentView = host
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        var frame = panel.frame
        if collapsed {
            expandedFrame = frame
            panel.minSize = Self.collapsedSize
            panel.styleMask.remove(.resizable)
            // Keep the top-right corner anchored so the capsule stays where the panel was.
            frame.origin.x = frame.maxX - Self.collapsedSize.width
            frame.origin.y = frame.maxY - Self.collapsedSize.height
            frame.size = Self.collapsedSize
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = Self.minExpandedSize
            let size = expandedFrame?.size ?? Self.expandedSize
            frame.origin.x = frame.maxX - size.width
            frame.origin.y = frame.maxY - size.height
            frame.size = size
        }
        panel.setFrame(frame, display: true, animate: true)
    }
}
