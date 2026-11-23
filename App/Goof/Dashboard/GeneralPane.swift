import AppKit
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "使用") {
                SettingsRow(title: "开机时自动启动", subtitle: model.launchAtLoginMessage ?? "登录 Mac 后 Goof 在菜单栏待命") {
                    SwitchToggle(label: "开机时自动启动",
                                 isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
                RowDivider()
                SettingsRow(title: "快速发弹幕",
                            subtitle: model.hotKeyProblem
                                ?? "在任何应用里按下快捷键，光标直接进入面板输入框；按 Esc 回到原来的应用。") {
                    HStack(spacing: 10) {
                        KeyChip(text: KeyCombo.composeShortcut.display)
                            .opacity(settings.hotKeyEnabled ? 1 : 0.45)
                        SwitchToggle(label: "快速发弹幕快捷键",
                                     isOn: Binding(get: { settings.hotKeyEnabled }, set: { model.setHotKeyEnabled($0) }))
                    }
                }
                RowDivider()
                SettingsRow(title: "屏幕共享和录屏时隐藏面板", subtitle: "开会共享屏幕时，别人看不到你的弹幕面板（你自己照常能看到）") {
                    SwitchToggle(label: "屏幕共享时隐藏面板",
                                 isOn: Binding(get: { settings.hideWhenSharing }, set: { model.setHideWhenSharing($0) }))
                }
                RowDivider()
                SettingsRow(title: "在菜单栏显示在线人数") {
                    SwitchToggle(label: "在菜单栏显示在线人数",
                                 isOn: Binding(get: { settings.showCountInMenuBar }, set: { settings.showCountInMenuBar = $0 }))
                }
            }

            SettingsSection(title: "服务器") {
                SettingsRow(title: serverTitle, subtitle: serverSubtitle) {
                    if model.isDemo {
                        Tag(text: "演示模式")
                    } else {
                        Tag(text: "已连接", color: Palette.green, background: Palette.green.opacity(0.14))
                    }
                }
                RowDivider()
                SettingsRow(title: "接入自己的服务器", subtitle: "实现一个 ChatService 协议就能接入 Supabase、Firebase 或自建的 WebSocket 服务。") {
                    Link("查看说明", destination: GoofLinks.backendGuide)
                }
            }

            SettingsSection(title: "关于") {
                SettingsRow(title: "Goof \(Self.version)", subtitle: "开源软件，MIT 协议") {
                    Link("GitHub", destination: GoofLinks.repository)
                }
                RowDivider()
                SettingsRow(title: "新手引导", subtitle: "重新看一遍第一次打开时的介绍") {
                    Button("重新开始") { model.restartOnboarding() }
                }
                RowDivider()
                SettingsRow(title: "退出 Goof", subtitle: "退出后不会进入任何房间，菜单栏图标也会消失") {
                    Button("退出") { NSApp.terminate(nil) }
                }
            }
        }
    }

    private var serverTitle: String {
        switch model.chat.kind {
        case .demo: "没有连接服务器"
        case .server(let name): "已连接 \(name)"
        }
    }

    private var serverSubtitle: String {
        switch model.chat.kind {
        case .demo: "现在房间里的人和消息都是在本机模拟的，方便体验和开发。你发的弹幕不会离开这台 Mac。"
        case .server: "消息通过这个服务器实时收发。"
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
