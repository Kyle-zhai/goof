import GoofCore
import SwiftUI

struct PrivacyPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "发言身份") {
                SettingsRow(title: "默认匿名发言",
                            subtitle: "别人只看到「匿名 · 橘猫·3f2」这类随机昵称，同一天同一个房间里不变，换个房间或第二天就换一个，无法关联到你。") {
                    SwitchToggle(label: "默认匿名发言",
                                 isOn: Binding(get: { model.postsAnonymously }, set: { model.setPostAnonymously($0) }))
                        .disabled(!model.profile.hasNickname)
                }
                if !model.profile.hasNickname {
                    RowDivider()
                    SettingsRow(title: "还没有昵称，所以现在只能匿名发言") {
                        Button("设置昵称") { model.dashboardPane = .profile }
                    }
                }
                RowDivider()
                SettingsRow(title: "随时切换", subtitle: "面板输入框左边的面具按钮可以临时切换匿名和实名。")
            }

            SettingsSection(title: "在线判定",
                            footer: "切到别的应用后有 45 秒宽限期，期间你显示为「离开」，回来不会掉线；锁屏或合上电脑会立刻离开房间。") {
                SettingsRow(title: "多久没操作算离开", subtitle: "前台虽然是这个应用，但人走开了，就不算在线人数里") {
                    ChipPicker(options: [1, 2, 5, 10].map { ChipOption(value: $0, title: "\($0) 分钟") },
                               selection: Binding(get: { settings.idleMinutes }, set: { model.setIdleMinutes($0) }))
                }
                RowDivider()
                PauseRow()
            }

            SettingsSection(title: "屏蔽列表") {
                if model.blocked.isEmpty {
                    SettingsRow(title: "没有屏蔽任何人", subtitle: "在弹幕上右键可以举报或屏蔽。匿名的人也能屏蔽，之后他的弹幕都不会再出现。")
                } else {
                    ForEach(Array(model.blocked.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            AvatarView(image: nil, name: user.label.replacingOccurrences(of: "匿名 · ", with: ""),
                                       accent: .gray, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.label).font(.system(size: 13, weight: .medium))
                                Text("屏蔽于 \(user.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("解除") { model.unblock(user) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
            }

            SettingsSection(title: "数据与权限") {
                SettingsRow(title: "Goof 读取什么",
                            subtitle: "只读取「当前前台是哪个应用」和「距离上次键盘鼠标操作过了几秒」。不读窗口内容、按键内容或屏幕，所以不需要任何系统权限。")
                RowDivider()
                SettingsRow(title: "Goof 发送什么",
                            subtitle: "只有你开启的应用会产生房间。别人只能看到同一个房间里的人和消息，永远看不到你在用哪些应用；不在白名单里的应用什么都不上传。")
                RowDivider()
                SettingsRow(title: "保存在本机的内容",
                            subtitle: "设置、个人资料和头像保存在这台 Mac 上。删除 Goof 后，再删掉「~/Library/Application Support/Goof」和「~/Library/Preferences/app.goof.Goof.plist」就能彻底清除。")
            }
        }
    }
}

private struct PauseRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isPaused {
            SettingsRow(title: "Goof 已暂停",
                        subtitle: model.pauseUntilText.map { "\($0)自动恢复，在这之前不会进入任何房间" } ?? "在你手动恢复之前，不会进入任何房间") {
                Button("恢复") { model.resume() }
            }
        } else {
            SettingsRow(title: "暂停 Goof", subtitle: "不进入任何房间，菜单栏图标会变成月亮") {
                Menu("暂停…") {
                    ForEach(PauseDuration.allCases) { duration in
                        Button(duration.title) { model.pause(duration) }
                    }
                }
                .menuStyle(.button)
                .fixedSize()
            }
        }
    }
}
