import SwiftUI

struct DashboardView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case apps = "应用"
        case profile = "个人资料"
        case privacy = "隐私与安全"
        case about = "关于"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .apps: return "square.grid.2x2"
            case .profile: return "person.crop.circle"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var selection: Pane? = .apps

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection ?? .apps {
            case .apps: AppsPane()
            case .profile: ProfilePane()
            case .privacy: PrivacyPane()
            case .about: AboutPane()
            }
        }
        .onDisappear { model.settings.hasCompletedOnboarding = true }
    }
}

private struct AboutPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kuro").font(.largeTitle.bold())
            Text("和正在用同一个应用的人，一起发弹幕。")
                .foregroundStyle(.secondary)
            Text(model.chat.isOffline
                 ? "当前是离线演示模式：没有配置服务器，弹幕和在线的人都是模拟的。"
                 : "已连接服务器。")
                .font(.callout)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
