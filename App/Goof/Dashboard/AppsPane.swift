import AppKit
import GoofCore
import SwiftUI

struct AppsPane: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: CatalogApp.Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NowCard()

            HStack(spacing: 10) {
                SearchField(text: $query)
                ChipPicker(options: categoryOptions, selection: $category)
            }

            let apps = filteredApps
            if apps.isEmpty {
                Text("没有找到这个应用。Goof 只为白名单里的应用开房间，想加新的可以到 GitHub 提交。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                    ForEach(apps) { app in
                        AppCard(app: app)
                    }
                }
            }

            HStack {
                Text("已开启 \(model.settings.allowedApps.count) 个应用 · 默认全部关闭，只有你打开的应用才会让你进房间")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.settings.allowedApps.isEmpty {
                    Button("全部关闭") { model.setApps(Array(model.settings.allowedApps), allowed: false) }
                        .controlSize(.small)
                }
            }

            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("浏览器、聊天、邮件、金融、健康类应用不提供房间")
                            .font(.system(size: 13, weight: .medium))
                        Text("这些应用里的内容太私人，「被看到在用它」本身就会泄露信息，所以 Goof 不会把它们放进白名单。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("想加一个应用？看看怎么提交", destination: GoofLinks.addAnApp)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.top, 2)
                    }
                }
                .padding(14)
            }
        }
    }

    private var categoryOptions: [ChipOption<CatalogApp.Category?>] {
        var options = [ChipOption<CatalogApp.Category?>(value: nil, title: "全部")]
        for category in CatalogApp.Category.allCases {
            options.append(ChipOption(value: category, title: category.title))
        }
        return options
    }

    /// Installed apps first, then the rest, each group in catalog order.
    private var filteredApps: [CatalogApp] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return AppCatalog.apps.enumerated()
            .filter { _, app in
                (category == nil || app.category == category)
                    && (needle.isEmpty || app.name.lowercased().contains(needle) || app.id.contains(needle))
            }
            .sorted { lhs, rhs in
                let left = AppIconCache.isInstalled(lhs.element) ? 0 : 1
                let right = AppIconCache.isInstalled(rhs.element) ? 0 : 1
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map { $0.element }
    }
}

private struct NowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let app = model.currentApp {
            let tint = NSColor(hex: app.tint) ?? .systemBlue
            HStack(spacing: 14) {
                AppTile(app: app, size: 46)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("你正在 \(app.name) 房间")
                        .font(.system(size: 16, weight: .bold))
                    Text((model.isAway ? "离开中 · " : "") + "\(model.onlineCount) 人在线，只有同房间的人能看到你")
                        .font(.system(size: 12))
                        .opacity(0.88)
                }
                Spacer()
                LiveBadge()
            }
            .padding(16)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient.accentBanner(tint))
            }
        } else {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: model.isPaused ? "moon.zzz.fill" : "bubble.left.and.bubble.right")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.chips))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isPaused ? "Goof 已暂停" : "当前不在任何房间")
                            .font(.system(size: 15, weight: .bold))
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.isPaused {
                        Button("恢复") { model.resume() }
                    } else if let app = model.frontmostDisabledApp {
                        Button("开启 \(app.name)") { model.setApp(app.id, allowed: true) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }
        }
    }

    private var reason: String {
        if model.isPaused {
            return model.pauseUntilText.map { "\($0)自动恢复，在这之前不会进入任何房间" } ?? "在你手动恢复之前，不会进入任何房间"
        }
        if let app = model.pendingApp { return "检测到你在用 \(app.name)，马上进入房间…" }
        if let app = model.frontmostDisabledApp { return "你刚才在用 \(app.name)，但还没开启它的弹幕" }
        if model.settings.allowedApps.isEmpty { return "在下面开启你常用的应用，切过去 3 秒后就会进入它的房间" }
        return "切到一个已开启的应用，3 秒后自动进入它的房间"
    }
}

private struct AppCard: View {
    @Environment(AppModel.self) private var model
    let app: CatalogApp

    var body: some View {
        let isOn = model.settings.allowedApps.contains(app.id)
        let installed = AppIconCache.isInstalled(app)
        let here = model.status.roomID == app.id
        HStack(spacing: 12) {
            AppTile(app: app, size: 38)
                .saturation(installed ? 1 : 0.35)
                .opacity(installed ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if here {
                    Text("● 你在这里 · \(model.onlineCount) 人")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.green)
                } else {
                    Text(app.category.title + (installed ? "" : " · 未安装"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            SwitchToggle(label: "允许 \(app.name)",
                         isOn: Binding(get: { isOn }, set: { model.setApp(app.id, allowed: $0) }))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? GoofColors.accent.opacity(0.55) : Palette.separator, lineWidth: isOn ? 1.5 : 1)
        }
        .shadow(color: isOn ? GoofColors.accent.opacity(0.1) : .black.opacity(0.03), radius: isOn ? 6 : 2, y: 1)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "搜索应用"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 150)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
    }
}
