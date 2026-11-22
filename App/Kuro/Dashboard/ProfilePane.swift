import AuthenticationServices
import CryptoKit
import SwiftUI

struct ProfilePane: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ProfileDraft()
    @State private var nonce = ""
    @State private var saving = false
    @State private var savedAt: Date?

    var body: some View {
        Form {
            if !model.isSignedIn {
                signInSection
            } else {
                Section {
                    HStack(spacing: 16) {
                        AvatarView(url: draft.avatarURL, name: draft.displayName, color: draft.accent, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.displayName.isEmpty ? "未设置昵称" : draft.displayName).font(.title2.bold())
                            Text("@\(draft.username.isEmpty ? "username" : draft.username)").foregroundStyle(.secondary)
                            if !draft.bio.isEmpty { Text(draft.bio).font(.callout) }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("预览：实名发言时别人看到的样子")
                }

                Section("账号") {
                    TextField("用户名（唯一，2–20 位字母、数字、下划线或中文）", text: $draft.username)
                    TextField("昵称（弹幕上显示的名字）", text: $draft.displayName)
                    TextField("一句话简介", text: $draft.bio)
                    TextField("头像链接（https://，之后会改为直接上传）", text: $draft.avatarString)
                    ColorPicker("主题色", selection: $draft.accent, supportsOpacity: false)
                }

                Section {
                    HStack {
                        if let error = draft.validationError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        } else if let savedAt {
                            Text("已保存 \(savedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !model.chat.isOffline {
                            Button("退出登录") { Task { await model.signOut() } }
                        }
                        Button(saving ? "保存中…" : "保存") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(saving || draft.validationError != nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("个人资料")
        .onAppear { draft = ProfileDraft(model.profile) }
        .onChange(of: model.profile) { _, p in draft = ProfileDraft(p) }
    }

    private var signInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("登录后可以发弹幕、设置你的直播间名片。").foregroundStyle(.secondary)
                SignInWithAppleButton(.signIn) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = []
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    guard case .success(let auth) = result,
                          let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let token = String(data: tokenData, encoding: .utf8) else { return }
                    Task { await model.signInWithApple(idToken: token, nonce: nonce) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(width: 220, height: 34)
            }
            .padding(.vertical, 6)
        }
    }

    private func save() {
        guard let id = model.chat.currentUserID, let profile = draft.profile(id: id) else { return }
        saving = true
        Task {
            if await model.saveProfile(profile) { savedAt = Date() }
            saving = false
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &rng)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ProfileDraft: Equatable {
    var username = ""
    var displayName = ""
    var bio = ""
    var avatarString = ""
    var accent = Color(red: 1, green: 0.35, blue: 0.37)
    var defaultAnonymous = true

    init() {}

    init(_ profile: UserProfile?) {
        guard let profile else { return }
        username = profile.username
        displayName = profile.displayName
        bio = profile.bio
        avatarString = profile.avatarURL?.absoluteString ?? ""
        accent = Color(hex: profile.accentColor) ?? accent
        defaultAnonymous = profile.defaultAnonymous
    }

    var avatarURL: URL? { avatarString.hasPrefix("https://") ? URL(string: avatarString) : nil }

    /// Mirrors the check constraints on `public.profiles`.
    var validationError: String? {
        if username.range(of: #"^[A-Za-z0-9_一-鿿]{2,20}$"#, options: .regularExpression) == nil {
            return "用户名需为 2–20 位字母、数字、下划线或中文"
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.count > 24 { return "昵称需为 1–24 个字" }
        if bio.count > 80 { return "简介最多 80 字" }
        if !avatarString.isEmpty && avatarURL == nil { return "头像链接需以 https:// 开头" }
        return nil
    }

    func profile(id: UUID) -> UserProfile? {
        guard validationError == nil else { return nil }
        return UserProfile(
            id: id, username: username,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            avatarURL: avatarURL, bio: bio, accentColor: accent.hexString, defaultAnonymous: defaultAnonymous)
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                color
                Text(String(name.first ?? "K")).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color, lineWidth: 2))
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .systemPink
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
