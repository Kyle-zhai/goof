import AppKit
import GoofCore
import SwiftUI

/// First run: what Goof does, which apps open rooms, and how you appear.
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
            GoofLogo(size: 76)
            VStack(spacing: 8) {
                Text("Chat with everyone using the same app as you")
                    .font(.system(size: 26, weight: .bold))
                Text("Goof lives in your menu bar. In Figma, you're in the Figma room. Switch to Xcode and you're in the Xcode room.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "checklist", tint: "#3A86FF", title: "Only in apps you turn on",
                        text: "Goof only checks which app is in front. It never reads windows, keystrokes or the screen, so it needs no permissions.")
                Feature(symbol: "eye.slash.fill", tint: "#2FBF71", title: "Nobody sees what you use",
                        text: "Only people in the same room know you're there. Nothing is sent for apps you haven't turned on.")
                Feature(symbol: "theatermasks.fill", tint: "#FF5A5F", title: "Anonymous by default",
                        text: "People only see a random name like “Anon Tabby·3f2”, different in every room, every day.")
            }
            .frame(maxWidth: 500)
            if model.isDemo {
                Label("Demo mode: no server is connected, so the people and messages are simulated on this Mac.", systemImage: "info.circle.fill")
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
                Text("Pick the apps that put you in a room")
                    .font(.system(size: 24, weight: .bold))
                Text("They all start off. Once an app is on, you join its room whenever it's in front and you're using it. You can change this any time in the Dashboard.")
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
                Text("\(model.settings.allowedApps.count) turned on")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !installed.isEmpty, installed.count < AppCatalog.apps.count {
                    Toggle("Show apps that aren't installed", isOn: $showAllApps)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 52)
    }

    private var hasNickname: Bool {
        !nickname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How do you want to show up?")
                    .font(.system(size: 24, weight: .bold))
                Text("A name is optional. Without one you can only post anonymously. You can add an avatar and accent color later in the Dashboard.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    LimitedField(label: "Name", prompt: "e.g. Yuzu", text: $nickname, limit: LocalProfile.maxDisplayName)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Post anonymously by default").font(.system(size: 13, weight: .medium))
                            Text(hasNickname ? "Switch any time with the mask button in the panel" : "Without a name you can only post anonymously")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        // Without a nickname you can only post anonymously, so show it as on.
                        SwitchToggle(label: "Post anonymously by default",
                                     isOn: Binding(get: { anonymous || !hasNickname }, set: { anonymous = $0 }))
                            .disabled(!hasNickname)
                    }
                    DanmakuPreviewStrip(messages: [previewMessage])
                }
                .padding(16)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Message style")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                ChipPicker(options: DanmakuStyle.allCases.map { ChipOption(value: $0, title: $0.title) },
                           selection: Binding(get: { model.settings.danmakuStyle }, set: { model.setStyle($0) }))
            }
            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("Press \(KeyCombo.composeShortcut.display) in any app to write a message, and Esc to go back. Goof's icon is in the menu bar at the top right of your screen.")
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
            return .sample("Hi everyone!", name: "Anon Tabby·3f2", anonymous: true, mine: true)
        }
        return .sample("Hi everyone!", name: name, accentHex: model.profile.profile.accentHex, mine: true)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index == step ? GoofColors.accent : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3), value: step)
            Spacer()
            if step > 0 {
                Button("Back") { withAnimation(.easeInOut(duration: 0.25)) { step -= 1 } }
                    .controlSize(.large)
            }
            Button(step < 2 ? (step == 0 ? "Get Started" : "Next") : "Start Using Goof") {
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
                    .foregroundStyle(isOn ? GoofColors.accent : Color.secondary.opacity(0.45))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? GoofColors.accent.opacity(0.6) : Palette.separator, lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
