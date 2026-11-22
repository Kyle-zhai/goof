import KuroCore
import SwiftUI

@main
struct KuroApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }

        Window("Kuro", id: "dashboard") {
            DashboardView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 460)
        }
        .defaultSize(width: 760, height: 520)
    }
}

private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .task {
                if !model.settings.hasCompletedOnboarding {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

private struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let app = model.currentApp {
            Text("\(app.name) 房间 · \(model.onlineCount) 人在线\(model.isAway ? "（离开中）" : "")")
        } else if model.settings.paused {
            Text("Kuro 已暂停")
        } else if model.settings.allowedApps.isEmpty {
            Text("还没有允许任何应用")
        } else {
            Text("当前应用不在你的允许列表里")
        }
        Divider()
        Toggle("显示弹幕面板", isOn: Binding(get: { model.settings.panelEnabled }, set: { model.setPanelEnabled($0) }))
        Toggle("暂停 Kuro", isOn: Binding(get: { model.settings.paused }, set: { model.setPaused($0) }))
        Divider()
        Button("打开 Dashboard…") {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("退出 Kuro") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
