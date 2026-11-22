import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilePane: View {
    @Environment(AppModel.self) private var model
    @State private var draft = LocalProfile.empty
    @State private var loaded = false
    @State private var avatarError: String?
    @State private var savedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProfileHero(draft: draft, avatarError: avatarError, pickAvatar: pickAvatar) {
                model.removeAvatar()
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        LimitedField(label: "昵称", prompt: "例如：阿柚", text: $draft.displayName,
                                     limit: LocalProfile.maxDisplayName)
                        LimitedField(label: "用户名（可选）", prompt: "例如：ayou_design", text: $draft.username, limit: 20)
                    }
                    LimitedField(label: "一句话简介（可选）", prompt: "介绍一下自己", text: $draft.bio, limit: LocalProfile.maxBio)
                    AccentPicker(hex: $draft.accentHex)
                }
                .padding(16)

                RowDivider(inset: 0)

                HStack(spacing: 10) {
                    footerText
                    Spacer(minLength: 8)
                    Button("还原") { draft = model.profile.profile }
                        .disabled(!hasChanges)
                    Button("保存") {
                        model.saveProfile(draft)
                        draft = model.profile.profile
                        savedAt = Date()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || draft.validationError != nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingsSection(title: "弹幕里的你",
                            footer: "实名时用你的昵称和主题色；匿名时只显示当天在这个房间里的随机昵称，别人无法知道是你。") {
                VStack(alignment: .leading, spacing: 10) {
                    PreviewLine(label: "实名", messages: [
                        .sample("大家好～", name: draft.displayName.isEmpty ? "你的昵称" : draft.displayName,
                                accentHex: draft.accentHex, mine: true),
                    ])
                    PreviewLine(label: "匿名", messages: [
                        .sample("大家好～", name: "匿名 · 橘猫·3f2", anonymous: true, mine: true),
                    ])
                }
                .padding(14)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = model.profile.profile
            loaded = true
        }
    }

    private var hasChanges: Bool { draft.trimmed != model.profile.profile }

    @ViewBuilder private var footerText: some View {
        if let error = draft.validationError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
        } else if let savedAt, Date().timeIntervalSince(savedAt) < 4, !hasChanges {
            Label("已保存", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.green)
        } else if draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("不填昵称也可以，只是只能匿名发言。")
                .foregroundStyle(.secondary)
        } else {
            Text(model.isDemo ? "资料保存在这台 Mac 上。接入服务器后，会作为公开资料给同房间的人看。"
                              : "保存后，同房间的人会看到新的资料。")
                .foregroundStyle(.secondary)
        }
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选一张图片作为头像，会自动裁成正方形"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.setAvatar(from: url)
            avatarError = nil
        } catch {
            avatarError = "这张图片打不开，换一张试试"
        }
    }
}

private struct ProfileHero: View {
    @Environment(AppModel.self) private var model
    let draft: LocalProfile
    let avatarError: String?
    let pickAvatar: () -> Void
    let removeAvatar: () -> Void

    var body: some View {
        let accent = Color(hex: draft.accentHex) ?? KuroColors.accent
        let accentNS = NSColor(hex: draft.accentHex) ?? .systemPink
        Card {
            ZStack {
                LinearGradient(colors: [accent, Color(nsColor: accentNS.darker(0.45))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            }
            .frame(height: 92)

            HStack(alignment: .top, spacing: 14) {
                // Space for the avatar, which hangs over the banner.
                Color.clear.frame(width: 72, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(draft.displayName.isEmpty ? "还没有昵称" : draft.displayName)
                            .font(.system(size: 19, weight: .bold))
                            .lineLimit(1)
                        Tag(text: "实名时显示", color: .secondary, background: Palette.chips)
                    }
                    Text(draft.username.isEmpty ? "没有设置用户名" : "@\(draft.username)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    if !draft.bio.isEmpty {
                        Text(draft.bio)
                            .font(.system(size: 12.5))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 10)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        if model.profile.avatar != nil {
                            Button("移除", action: removeAvatar)
                        }
                        Button("更换头像…", action: pickAvatar)
                    }
                    if let avatarError {
                        Text(avatarError).font(.system(size: 11)).foregroundStyle(Palette.warning)
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .overlay(alignment: .topLeading) {
                AvatarView(image: model.profile.avatar, name: draft.displayName.isEmpty ? "?" : draft.displayName,
                           accent: accent, size: 72, ring: 4)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .padding(.leading, 18)
                    .offset(y: -36)
            }
        }
    }
}

/// A labeled text field with a live character count.
struct LimitedField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(text.count)/\(limit)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(text.count > limit ? Palette.warning : Color.secondary.opacity(0.7))
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccentPicker: View {
    @Binding var hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("主题色（昵称和头像框的颜色）")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(KuroColors.presets, id: \.self) { preset in
                    let selected = preset.caseInsensitiveCompare(hex) == .orderedSame
                    Button {
                        hex = preset
                    } label: {
                        Circle()
                            .fill(Color(hex: preset) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay { Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : 0) }
                            .overlay { Circle().strokeBorder(Color(hex: preset) ?? .gray, lineWidth: selected ? 1.5 : 0).padding(-3) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("主题色 \(preset)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                ColorPicker("自定义", selection: Binding(get: { Color(hex: hex) ?? KuroColors.accent },
                                                     set: { hex = $0.hexString }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .help("自定义颜色")
            }
        }
    }
}

private struct PreviewLine: View {
    let label: String
    let messages: [ChatMessage]

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            DanmakuPreviewStrip(messages: messages)
        }
    }
}
