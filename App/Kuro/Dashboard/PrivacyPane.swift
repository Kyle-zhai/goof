import SwiftUI

struct PrivacyPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("发言身份") {
                Toggle("默认匿名发言", isOn: Binding(get: { model.settings.postAnonymously }, set: { model.setPostAnonymously($0) }))
                Text("匿名时别人只会看到「匿名 · 橘猫·3f2」这样的随机昵称，同一天同一个房间内保持不变，无法关联到你的账号。面板输入框左边的面具按钮可以随时切换。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("在线判定") {
                Picker("多久没操作算离开", selection: Binding(get: { model.settings.idleThresholdMinutes }, set: { model.setIdleThreshold(minutes: $0) })) {
                    Text("1 分钟").tag(1)
                    Text("2 分钟").tag(2)
                    Text("5 分钟").tag(5)
                    Text("10 分钟").tag(10)
                }
                Toggle("暂停 Kuro（不进入任何房间）", isOn: Binding(get: { model.settings.paused }, set: { model.setPaused($0) }))
                Text("Kuro 只读取「当前前台是哪个应用」和「距离上次键盘鼠标操作过了几秒」，不读取窗口内容、按键内容或屏幕，因此不需要任何系统权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("弹幕") {
                Toggle("显示弹幕面板", isOn: Binding(get: { model.settings.panelEnabled }, set: { model.setPanelEnabled($0) }))
                Slider(value: Binding(get: { model.settings.danmakuSpeed }, set: { model.setSpeed($0) }), in: 50...160) {
                    Text("滚动速度")
                }
            }

            Section("屏蔽列表") {
                if model.blocks.isEmpty {
                    Text("没有屏蔽任何人。在弹幕上右键可以举报或屏蔽。").foregroundStyle(.secondary)
                } else {
                    ForEach(model.blocks) { block in
                        HStack {
                            Text(block.label)
                            Spacer()
                            Text(block.createdAt, style: .date).foregroundStyle(.tertiary)
                            Button("解除") { model.unblock(block) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("隐私与安全")
    }
}
