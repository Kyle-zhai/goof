import AppKit
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Behavior") {
                SettingsRow(title: "Launch at login", subtitle: model.launchAtLoginMessage ?? "Goof waits in the menu bar after you log in") {
                    SwitchToggle(label: "Launch at login",
                                 isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
                RowDivider()
                SettingsRow(title: "Quick message",
                            subtitle: model.hotKeyProblem
                                ?? "Press the shortcut in any app to jump to the panel's input field. Press Esc to go back.") {
                    HStack(spacing: 10) {
                        KeyChip(text: KeyCombo.composeShortcut.display)
                            .opacity(settings.hotKeyEnabled ? 1 : 0.45)
                        SwitchToggle(label: "Quick message shortcut",
                                     isOn: Binding(get: { settings.hotKeyEnabled }, set: { model.setHotKeyEnabled($0) }))
                    }
                }
                RowDivider()
                SettingsRow(title: "Hide the panel when sharing or recording the screen", subtitle: "People in a meeting won't see your panel. You still will.") {
                    SwitchToggle(label: "Hide the panel when sharing the screen",
                                 isOn: Binding(get: { settings.hideWhenSharing }, set: { model.setHideWhenSharing($0) }))
                }
                RowDivider()
                SettingsRow(title: "Show the online count in the menu bar") {
                    SwitchToggle(label: "Show the online count in the menu bar",
                                 isOn: Binding(get: { settings.showCountInMenuBar }, set: { settings.showCountInMenuBar = $0 }))
                }
            }

            SettingsSection(title: "Server") {
                SettingsRow(title: serverTitle, subtitle: serverSubtitle) {
                    if model.isDemo {
                        Tag(text: "Demo mode")
                    } else {
                        Tag(text: "Connected", color: Palette.green, background: Palette.green.opacity(0.14))
                    }
                }
                RowDivider()
                SettingsRow(title: "Connect your own server", subtitle: "Implement the ChatService protocol to use Supabase, Firebase or your own WebSocket service.") {
                    Link("Read the Guide", destination: GoofLinks.backendGuide)
                }
            }

            SettingsSection(title: "About") {
                SettingsRow(title: "Goof \(Self.version)", subtitle: "Open source under the MIT License") {
                    Link("GitHub", destination: GoofLinks.repository)
                }
                RowDivider()
                SettingsRow(title: "Welcome tour", subtitle: "See the introduction from your first launch again") {
                    Button("Show Again") { model.restartOnboarding() }
                }
                RowDivider()
                SettingsRow(title: "Quit Goof", subtitle: "You won't join any rooms, and the menu bar icon goes away") {
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
    }

    private var serverTitle: String {
        switch model.chat.kind {
        case .demo: "No server connected"
        case .server(let name): "Connected to \(name)"
        }
    }

    private var serverSubtitle: String {
        switch model.chat.kind {
        case .demo: "The people and messages in rooms are simulated on this Mac, for trying Goof out and for development. Your messages never leave this Mac."
        case .server: "Messages are sent and received live through this server."
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
