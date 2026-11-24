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
                        LimitedField(label: "Name", prompt: "e.g. Yuzu", text: $draft.displayName,
                                     limit: LocalProfile.maxDisplayName)
                        LimitedField(label: "Username (optional)", prompt: "e.g. yuzu_design", text: $draft.username, limit: 20)
                    }
                    LimitedField(label: "Bio (optional)", prompt: "A line about you", text: $draft.bio, limit: LocalProfile.maxBio)
                    AccentPicker(hex: $draft.accentHex)
                }
                .padding(16)

                RowDivider(inset: 0)

                HStack(spacing: 10) {
                    footerText
                    Spacer(minLength: 8)
                    Button("Revert") { draft = model.profile.profile }
                        .disabled(!hasChanges)
                    Button("Save") {
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

            SettingsSection(title: "How you appear",
                            footer: "Named messages use your name and accent color. Anonymous ones only show today's random name for this room, so nobody can tell it's you.") {
                VStack(alignment: .leading, spacing: 10) {
                    PreviewLine(label: "Named", messages: [
                        .sample("Hi everyone!", name: draft.displayName.isEmpty ? "Your name" : draft.displayName,
                                accentHex: draft.accentHex, mine: true),
                    ])
                    PreviewLine(label: "Anonymous", messages: [
                        .sample("Hi everyone!", name: "Anon Tabby·3f2", anonymous: true, mine: true),
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
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.green)
        } else if draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("A name is optional, but without one you can only post anonymously.")
                .foregroundStyle(.secondary)
        } else {
            Text(model.isDemo ? "Your profile is stored on this Mac. With a server connected, people in your room will see it."
                              : "Once you save, people in your room see the new profile.")
                .foregroundStyle(.secondary)
        }
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image for your avatar. It will be cropped to a square."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.setAvatar(from: url)
            avatarError = nil
        } catch {
            avatarError = "Couldn't open this image. Try another one."
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
        let accent = Color(hex: draft.accentHex) ?? GoofColors.accent
        let accentNS = NSColor(hex: draft.accentHex) ?? .systemPink
        Card {
            LinearGradient.accentBanner(accentNS)
                .frame(height: 92)

            HStack(alignment: .top, spacing: 14) {
                // Space for the avatar, which hangs over the banner.
                Color.clear.frame(width: 72, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(draft.displayName.isEmpty ? "No name yet" : draft.displayName)
                            .font(.system(size: 19, weight: .bold))
                            .lineLimit(1)
                        Tag(text: "Shown when named", color: .secondary, background: Palette.chips)
                    }
                    Text(draft.username.isEmpty ? "No username" : "@\(draft.username)")
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
                            Button("Remove", action: removeAvatar)
                        }
                        Button("Change Avatar…", action: pickAvatar)
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
            Text("Accent color (your name and avatar ring)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(GoofColors.presets, id: \.self) { preset in
                    let selected = preset.caseInsensitiveCompare(hex) == .orderedSame
                    Button {
                        hex = preset
                    } label: {
                        AccentSwatch(hex: preset, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accent color \(preset)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                ColorPicker("Custom", selection: Binding(get: { Color(hex: hex) ?? GoofColors.accent },
                                                     set: { hex = $0.hexString }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .help("Custom color")
            }
        }
    }
}

private struct AccentSwatch: View {
    let hex: String
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 24, height: 24)
            // A hairline keeps dark presets visible on a dark background.
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }
            .overlay {
                if selected {
                    Circle().strokeBorder(Color.white, lineWidth: 2.5)
                    Circle().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5).padding(-3)
                }
            }
            .contentShape(Circle())
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
                .frame(width: 72, alignment: .leading)
            DanmakuPreviewStrip(messages: messages)
        }
    }
}
