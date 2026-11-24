import AppKit
import SwiftUI

/// A borderless, non-activating, always-on-top panel. Non-activating matters:
/// typing in it does not make Goof the frontmost app, so the user stays in the
/// room of the app they are actually using.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = false
        // ⌘H while the dashboard is in front must not hide the panel too.
        canHide = false
        appearance = NSAppearance(named: .darkAqua)
    }

    // Borderless windows refuse key status by default; the text field needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        StandardEditKeys.handle(event, in: self) || super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class FloatingPanelController {
    static let defaultSize = NSSize(width: 340, height: 220)
    static let collapsedSize = NSSize(width: 200, height: 36)
    static let minSize = NSSize(width: 260, height: 150)
    private static let autosaveName = "GoofFloatingPanel"

    private let panel: FloatingPanel
    private var expandedSize: NSSize
    private var isCollapsed = false
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        expandedSize = Self.defaultSize
        panel.minSize = Self.minSize

        let host = NSHostingView(rootView: PanelView().environment(model))
        host.sizingOptions = []
        panel.contentView = host

        if !panel.setFrameUsingName(Self.autosaveName) { placeAtDefaultPosition() }
        panel.setFrameAutosaveName(Self.autosaveName)
        expandedSize = panel.frame.size
        ensureOnScreen()

        // Unplugging a display can strand the panel off screen.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureOnScreen() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func apply(hideWhenSharing: Bool) {
        // Keeps the panel out of screen sharing and recordings that respect it.
        panel.sharingType = hideWhenSharing ? .none : .readOnly
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Dims the panel while the user is away from the room's app.
    func setDimmed(_ dimmed: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = dimmed ? 0.72 : 1
        }
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        var frame = panel.frame
        if collapsed {
            expandedSize = frame.size
            // Don't let the capsule size overwrite the saved panel size.
            panel.setFrameAutosaveName("")
            panel.minSize = Self.collapsedSize
            panel.styleMask.remove(.resizable)
            frame.origin.x = frame.maxX - Self.collapsedSize.width
            frame.origin.y = frame.maxY - Self.collapsedSize.height
            frame.size = Self.collapsedSize
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = Self.minSize
            frame.origin.x = frame.maxX - expandedSize.width
            frame.origin.y = frame.maxY - expandedSize.height
            frame.size = expandedSize
        }
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
        if !collapsed {
            panel.setFrameAutosaveName(Self.autosaveName)
            ensureOnScreen()
        }
    }

    /// For a panel that ended up somewhere awkward: back to the default corner.
    func resetPosition() {
        if isCollapsed { setCollapsed(false, animated: false) }
        expandedSize = Self.defaultSize
        placeAtDefaultPosition()
        panel.saveFrame(usingName: Self.autosaveName)
    }

    /// Puts the keyboard focus in the panel without activating Goof.
    func focus() {
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.makeKey()
    }

    /// Gives the keyboard back to the app the user was typing in.
    func returnFocus() {
        guard panel.isKeyWindow else { return }
        let behavior = panel.animationBehavior
        panel.animationBehavior = .none
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        panel.animationBehavior = behavior
    }

    private func placeAtDefaultPosition() {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = isCollapsed ? Self.collapsedSize : expandedSize
        panel.setFrame(NSRect(x: screen.maxX - size.width - 24, y: screen.minY + 96, width: size.width, height: size.height), display: false)
    }

    private func ensureOnScreen() {
        let frame = panel.frame.insetBy(dx: 40, dy: 12)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            placeAtDefaultPosition()
        }
    }
}
