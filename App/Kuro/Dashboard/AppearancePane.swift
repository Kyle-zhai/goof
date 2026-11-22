import AppKit
import SwiftUI

struct AppearancePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("样式")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 12) {
                    ForEach(DanmakuStyle.allCases) { style in
                        StyleCard(style: style, selected: settings.danmakuStyle == style) {
                            model.setStyle(style)
                        }
                    }
                }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, settings.danmakuStyle == .scroll, !model.isSnapshot {
                    Label("系统开启了「减弱动态效果」，推荐用「规整列表」", systemImage: "figure.walk.motion")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            SettingsSection(title: "细节") {
                SettingsRow(title: "滚动速度",
                            subtitle: settings.danmakuStyle == .scroll ? "弹幕每秒移动的距离" : "只在「滚动弹幕」样式下生效") {
                    ValueSlider(label: "滚动速度",
                                value: Binding(get: { settings.danmakuSpeed }, set: { model.setSpeed($0) }),
                                range: 50...160, step: 5) { "\(Int($0))" }
                        .disabled(settings.danmakuStyle != .scroll)
                }
                RowDivider()
                SettingsRow(title: "字号") {
                    ChipPicker(options: DanmakuFontSize.allCases.map { ChipOption(value: $0, title: $0.title) },
                               selection: Binding(get: { settings.fontSize }, set: { model.setFontSize($0) }))
                }
                RowDivider()
                SettingsRow(title: "面板背景浓度", subtitle: "越低越通透，越高越容易看清文字") {
                    ValueSlider(label: "面板背景浓度",
                                value: Binding(get: { settings.panelOpacity }, set: { settings.panelOpacity = $0 }),
                                range: 0.35...0.9, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
                }
                RowDivider()
                SettingsRow(title: "进房间时回放最近的弹幕", subtitle: "以较淡的样式显示，让你知道大家刚才在聊什么") {
                    SwitchToggle(label: "回放最近的弹幕",
                                 isOn: Binding(get: { settings.replayHistory }, set: { settings.replayHistory = $0 }))
                }
                RowDivider()
                SettingsRow(title: "显示弹幕面板", subtitle: "关掉后只保留菜单栏图标，房间照常进出") {
                    SwitchToggle(label: "显示弹幕面板",
                                 isOn: Binding(get: { settings.panelEnabled }, set: { model.setPanelEnabled($0) }))
                }
            }

            SettingsSection(title: "面板",
                            footer: "鼠标停在弹幕上会暂停滚动，方便看清或右键举报；拖动标题栏或弹幕区域可以移动面板，右下角可以调整大小。") {
                SettingsRow(title: "找不到面板了？", subtitle: "把面板放回屏幕右下角，恢复默认大小") {
                    Button("重置位置") { model.resetPanelPosition() }
                }
            }
        }
    }
}

private struct StyleCard: View {
    let style: DanmakuStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.24), Color(red: 0.1, green: 0.1, blue: 0.14)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipped()
                    .environment(\.colorScheme, .dark)
                HStack(spacing: 10) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? KuroColors.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.title).font(.system(size: 13, weight: .semibold))
                        Text(style.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? KuroColors.accent : Color.secondary.opacity(0.5))
                }
                .padding(12)
            }
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? KuroColors.accent : Palette.separator, lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected ? KuroColors.accent.opacity(0.15) : .black.opacity(0.03), radius: selected ? 8 : 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch style {
        case .scroll:
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.scrollSamples.enumerated()), id: \.offset) { _, sample in
                        if let image = DanmakuBubble.nsImage(for: sample.message, fontSize: 12) {
                            Image(nsImage: image)
                                .offset(x: width * sample.x, y: sample.y)
                        }
                    }
                }
            }
        case .stack:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.stackSamples) { message in
                    StackRow(message: message, fontSize: 12)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 8)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.4)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private static let scrollSamples: [(message: ChatMessage, x: CGFloat, y: CGFloat)] = [
        (.sample("大家下午好～", name: "阿柚", accentHex: "#FF7A85"), 0.5, 12),
        (.sample("终于跑通了！！", name: "Leo", accentHex: "#FF9F1C"), 0.08, 36),
        (.sample("+1", name: "Kiki", accentHex: "#FF6FB5"), 0.72, 36),
        (.sample("这个功能好好用", name: "小林", accentHex: "#5AC8FA"), 0.3, 60),
        (.sample("今天第三杯咖啡", name: "Momo", accentHex: "#FFB347"), 0.02, 84),
        (.sample("同感", name: "匿名 · 水獭·a3f", anonymous: true), 0.66, 84),
    ]

    private static let stackSamples: [ChatMessage] = [
        .sample("今天第三杯咖啡", name: "Momo", accentHex: "#FFB347"),
        .sample("大家下午好～", name: "阿柚", accentHex: "#FF7A85"),
        .sample("终于跑通了！！", name: "Leo", accentHex: "#FF9F1C"),
        .sample("这个功能好好用", name: "小林", accentHex: "#5AC8FA"),
    ]
}
