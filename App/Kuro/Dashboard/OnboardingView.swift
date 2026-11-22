import AppKit
import KuroCore
import SwiftUI

/// First run: what Kuro does, which apps open rooms, and how you appear.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Int
    @State private var nickname = ""
    @State private var anonymous = true
    @State private var showAllApps = false

    init(step: Int = 0) {
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: apps
                default: identity
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            footer
        }
        .background(Palette.paneBackground)
        .ignoresSafeArea()
        .onAppear {
            nickname = model.profile.profile.displayName
            anonymous = model.settings.postAnonymously
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)
            KuroLogo(size: 76)
            VStack(spacing: 8) {
                Text("和正在用同一个应用的人，一起发弹幕")
                    .font(.system(size: 26, weight: .bold))
                Text("Kuro 住在菜单栏里。你在用 Figma，就进 Figma 房间；切到 Xcode，就换到 Xcode 房间。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "checklist", tint: "#3A86FF", title: "只在你开启的应用里",
                        text: "只看「当前前台是哪个应用」，不读窗口内容、按键或屏幕，所以不需要任何系统权限。")
                Feature(symbol: "eye.slash.fill", tint: "#2FBF71", title: "别人看不到你在用什么",
                        text: "只有同一个房间里的人知道你也在；没开启的应用什么都不上传。")
                Feature(symbol: "theatermasks.fill", tint: "#FF5A5F", title: "默认匿名",
                        text: "匿名时别人只看到「匿名 · 橘猫·3f2」这样的随机昵称，每天每个房间都不一样。")
            }
            .frame(maxWidth: 500)
            if model.isDemo {
                Label("演示模式：还没有连接服务器，房间里的人和消息是在本机模拟的。", systemImage: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Palette.chips))
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 40)
    }

    private var apps: some View {
        let installed = AppCatalog.apps.filter { AppIconCache.isInstalled($0) }
        let list = showAllApps || installed.isEmpty ? AppCatalog.apps : installed
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择会让你进入房间的应用")
                    .font(.system(size: 24, weight: .bold))
                Text("全部默认关闭。打开之后，只要这个应用在前台、你在操作，就会进入它的房间。之后随时可以在 Dashboard 里改。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(list) { app in
                        OnboardingAppTile(app: app)
                    }
                }
                .padding(2)
            }
            HStack {
                Text("已开启 \(model.settings.allowedApps.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !installed.isEmpty, installed.count < AppCatalog.apps.count {
                    Toggle("也显示没安装的应用", isOn: $showAllApps)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 52)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("你想怎么出现在弹幕里？")
                    .font(.system(size: 24, weight: .bold))
                Text("昵称可以不填，不填就只能匿名发言。之后可以在 Dashboard 里设置头像和主题色。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    LimitedField(label: "昵称", prompt: "例如：阿柚", text: $nickname, limit: LocalProfile.maxDisplayName)
                    Toggle(isOn: $anonymous) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("默认匿名发言").font(.system(size: 13, weight: .medium))
                            Text("面板里随时可以点面具按钮切换").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                    DanmakuPreviewStrip(messages: [previewMessage])
                }
                .padding(16)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("弹幕样式")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                ChipPicker(options: DanmakuStyle.allCases.map { ChipOption(value: $0, title: $0.title) },
                           selection: Binding(get: { model.settings.danmakuStyle }, set: { model.setStyle($0) }))
            }
            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("在任何应用里按 \(KeyCombo.composeShortcut.display) 直接发弹幕，按 Esc 回去。Kuro 的图标在屏幕右上角的菜单栏里。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .padding(.top, 52)
        .frame(maxWidth: 640)
    }

    private var previewMessage: ChatMessage {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        if anonymous || name.isEmpty {
            return .sample("大家好～", name: "匿名 · 橘猫·3f2", anonymous: true, mine: true)
        }
        return .sample("大家好～", name: name, accentHex: model.profile.profile.accentHex, mine: true)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index == step ? KuroColors.accent : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3), value: step)
            Spacer()
            if step > 0 {
                Button("上一步") { withAnimation(.easeInOut(duration: 0.25)) { step -= 1 } }
                    .controlSize(.large)
            }
            Button(step < 2 ? (step == 0 ? "开始设置" : "下一步") : "开始使用") {
                if step < 2 {
                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                } else {
                    finish()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Palette.card)
        .overlay(alignment: .top) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }

    private func finish() {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        var profile = model.profile.profile
        profile.displayName = String(name.prefix(LocalProfile.maxDisplayName))
        if profile.validationError == nil, profile != model.profile.profile {
            model.saveProfile(profile)
        }
        model.setPostAnonymously(anonymous || !model.profile.hasNickname)
        model.finishOnboarding()
    }
}

private struct Feature: View {
    let symbol: String
    let tint: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: tint) ?? .gray)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingAppTile: View {
    @Environment(AppModel.self) private var model
    let app: CatalogApp

    var body: some View {
        let isOn = model.settings.allowedApps.contains(app.id)
        Button {
            model.setApp(app.id, allowed: !isOn)
        } label: {
            HStack(spacing: 10) {
                AppTile(app: app, size: 30)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isOn ? KuroColors.accent : Color.secondary.opacity(0.45))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? KuroColors.accent.opacity(0.6) : Palette.separator, lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
