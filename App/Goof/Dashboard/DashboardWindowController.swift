import AppKit
import SwiftUI

final class DashboardWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return StandardEditKeys.handle(event, in: self) || super.performKeyEquivalent(with: event)
    }
}

/// The dashboard (and first-run onboarding) window. While it is open Goof
/// shows up in the Dock and the app switcher like a normal app; when it
/// closes Goof goes back to living in the menu bar.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 860, height: 600)

    private let window: DashboardWindow
    private var previousApp: NSRunningApplication?

    init(model: AppModel) {
        window = DashboardWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        super.init()
        window.title = "Goof"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.minSize = NSSize(width: 780, height: 540)
        let host = NSHostingView(rootView: DashboardRoot().environment(model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("GoofDashboard")
    }

    func show() {
        if !window.isVisible, let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Hand the keyboard back to whatever the user was doing before.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            _ = previousApp.activate(options: [])
        }
        previousApp = nil
    }
}
