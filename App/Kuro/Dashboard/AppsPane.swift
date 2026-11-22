import KuroCore
import SwiftUI

struct AppsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("只有你勾选的应用会让你进入房间。你在其他应用里时，Kuro 什么都不会上传，别人也永远看不到你在用什么应用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(CatalogApp.Category.allCases, id: \.self) { category in
                let apps = AppCatalog.defaultApps.filter { $0.category == category }
                if !apps.isEmpty {
                    Section(category.rawValue) {
                        ForEach(apps) { app in row(app) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("应用")
    }

    private func row(_ app: CatalogApp) -> some View {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
        let isOn = Binding(
            get: { model.settings.allowedApps.contains(app.bundleID) },
            set: { model.setApp(app.bundleID, allowed: $0) })
        return Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                AppIcon(bundleID: app.bundleID, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    if !installed {
                        Text("未安装").font(.caption).foregroundStyle(.tertiary)
                    } else if model.status.roomID == app.bundleID {
                        Text("你正在这个房间 · \(model.onlineCount) 人在线").font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
