import AppKit
import KuroCore
import SwiftUI

@main
struct KuroApp: App {
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
        let bundleID = Bundle.main.bundleIdentifier ?? AppCatalog.kuroBundleID
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        model.start()
    }

    /// Opening Kuro again from Finder or Spotlight shows the dashboard.
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
        .accessibilityLabel("Kuro，\(model.statusSummary)")
    }
}

private struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.statusSummary)
        if model.isDemo {
            Text("演示模式：房间里的人和消息是模拟的")
        }
        if let app = model.frontmostDisabledApp, !model.isPaused {
            Button("在 \(app.name) 里开启弹幕") { model.setApp(app.id, allowed: true) }
        }

        Divider()

        Toggle("显示弹幕面板", isOn: Binding(get: { model.settings.panelEnabled },
                                         set: { model.setPanelEnabled($0) }))
        Picker("弹幕样式", selection: Binding(get: { model.settings.danmakuStyle },
                                          set: { model.setStyle($0) })) {
            ForEach(DanmakuStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        Button("快速发弹幕（\(KeyCombo.composeShortcut.display)）") { model.focusComposer() }
            .disabled(!model.isInRoom)

        Divider()

        if model.isPaused {
            Button(model.pauseUntilText.map { "恢复 Kuro（原定\($0)恢复）" } ?? "恢复 Kuro") { model.resume() }
        } else {
            Menu("暂停 Kuro") {
                ForEach(PauseDuration.allCases) { duration in
                    Button(duration.title) { model.pause(duration) }
                }
            }
        }
        Button("打开 Dashboard…") { model.showDashboard() }
            .keyboardShortcut(",")

        Divider()

        Button("退出 Kuro") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
