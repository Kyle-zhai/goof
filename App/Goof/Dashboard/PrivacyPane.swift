import GoofCore
import SwiftUI

struct PrivacyPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Identity") {
                SettingsRow(title: "Post anonymously by default",
                            subtitle: "People only see a random name like “Anon Tabby·3f2”. It stays the same in one room for a day and changes in other rooms and the next day, so it can't be traced back to you.") {
                    SwitchToggle(label: "Post anonymously by default",
                                 isOn: Binding(get: { model.postsAnonymously }, set: { model.setPostAnonymously($0) }))
                        .disabled(!model.profile.hasNickname)
                }
                if !model.profile.hasNickname {
                    RowDivider()
                    SettingsRow(title: "You don't have a name yet, so you can only post anonymously") {
                        Button("Set Name") { model.dashboardPane = .profile }
                    }
                }
                RowDivider()
                SettingsRow(title: "Switch any time", subtitle: "The mask button left of the panel's input field switches between anonymous and named.")
            }

            SettingsSection(title: "Presence",
                            footer: "After you switch to another app you have 45 seconds to come back: you show as away and keep your seat. Locking the screen or closing the lid leaves the room right away.") {
                SettingsRow(title: "Count me as away after", subtitle: "If the app is in front but you've stepped away, you don't count as online") {
                    ChipPicker(options: [1, 2, 5, 10].map { ChipOption(value: $0, title: "\($0) min") },
                               selection: Binding(get: { settings.idleMinutes }, set: { model.setIdleMinutes($0) }))
                }
                RowDivider()
                PauseRow()
            }

            SettingsSection(title: "Blocked") {
                if model.blocked.isEmpty {
                    SettingsRow(title: "Nobody blocked", subtitle: "Right-click a message to report or block its author. Anonymous people can be blocked too, and you won't see their messages again.")
                } else {
                    ForEach(Array(model.blocked.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            AvatarView(image: nil, name: user.label.replacingOccurrences(of: AnonymousAlias.prefix, with: ""),
                                       accent: .gray, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.label).font(.system(size: 13, weight: .medium))
                                Text("Blocked \(user.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unblock") { model.unblock(user) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
            }

            SettingsSection(title: "Data and permissions") {
                SettingsRow(title: "What Goof reads",
                            subtitle: "Only which app is in front, and how many seconds since you last used the keyboard or mouse. Never window contents, keystrokes or the screen, so it needs no system permissions.")
                RowDivider()
                SettingsRow(title: "What Goof sends",
                            subtitle: "Only apps you turn on create rooms. Others only see the people and messages in the same room, never which apps you use. Nothing is sent for apps that aren't on the list.")
                RowDivider()
                SettingsRow(title: "What's stored on this Mac",
                            subtitle: "Your settings, profile and avatar. To remove everything after deleting Goof, also delete ~/Library/Application Support/Goof and ~/Library/Preferences/app.goof.Goof.plist.")
            }
        }
    }
}

private struct PauseRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isPaused {
            SettingsRow(title: "Goof is paused",
                        subtitle: model.pauseUntilText.map { "Paused until \($0). You won't join any room before then" } ?? "You won't join any room until you resume") {
                Button("Resume") { model.resume() }
            }
        } else {
            SettingsRow(title: "Pause Goof", subtitle: "Join no rooms for a while. The menu bar icon turns into a moon") {
                Menu("Pause…") {
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
