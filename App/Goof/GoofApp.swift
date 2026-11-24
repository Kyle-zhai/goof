import AppKit
import GoofCore
import SwiftUI

@main
struct GoofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environment(delegate.model)
        } label: {
            MenuBarLabel()
                .environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotRenderer.isRequested {
            SnapshotRenderer.run()
            return
        }
        // Launched twice (say from Downloads and from Applications): keep the first one.
        let bundleID = Bundle.main.bundleIdentifier ?? AppCatalog.goofBundleID
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        model.start()
    }

    /// Opening Goof again from Finder or Spotlight shows the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showDashboard()
        return false
    }
}

private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.menuBarSymbol)
            if model.settings.showCountInMenuBar, model.isInRoom, !model.isAway {
                Text("\(model.onlineCount)").monospacedDigit()
            }
        }
        .accessibilityLabel("Goof, \(model.statusSummary)")
    }
}

private struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.statusSummary)
        if model.isDemo {
            Text("Demo mode: the people and messages are simulated")
        }
        if let app = model.frontmostDisabledApp, !model.isPaused {
            Button("Turn On Goof for \(app.name)") { model.setApp(app.id, allowed: true) }
        }

        Divider()

        Toggle("Show Panel", isOn: Binding(get: { model.settings.panelEnabled },
                                         set: { model.setPanelEnabled($0) }))
        Picker("Style", selection: Binding(get: { model.settings.danmakuStyle },
                                          set: { model.setStyle($0) })) {
            ForEach(DanmakuStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        Button("Write a Message (\(KeyCombo.composeShortcut.display))") { model.focusComposer() }
            .disabled(!model.isInRoom)

        Divider()

        if model.isPaused {
            Button(model.pauseUntilText.map { "Resume Goof (paused until \($0))" } ?? "Resume Goof") { model.resume() }
        } else {
            Menu("Pause Goof") {
                ForEach(PauseDuration.allCases) { duration in
                    Button(duration.title) { model.pause(duration) }
                }
            }
        }
        Button("Open Dashboard…") { model.showDashboard() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Goof") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
