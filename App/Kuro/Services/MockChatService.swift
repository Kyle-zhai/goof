import Foundation

/// Offline backend: fake people chatting in every room. Used automatically
/// when no Supabase URL is configured, so the app runs out of the box.
@MainActor
final class MockChatService: ChatService {
    var onEvent: ((ChatEvent) -> Void)?
    private(set) var isSignedIn = true
    let isOffline = true
    let currentUserID: UUID? = UUID()

    private var room: String?
    private var timer: Timer?
    private var members: [RoomMember] = []
    private var me: RoomMember?
    private var profile: UserProfile?
    private var blocks: [BlockedUser] = []
    private var blockedNames: Set<String> = []

    private static let names = ["阿柚", "Momo", "小林", "debug 侠", "像素猫", "Leo", "夜猫子", "Kiki", "匿名 · 水獭·a3f", "匿名 · 柴犬·19c"]
    private static let lines = [
        "有人也在赶 deadline 吗", "这个功能好好用", "今天第三杯咖啡了", "求推荐一个好用的配色",
        "终于跑通了！！", "大家下午好～", "这个 bug 我找了两小时", "有人一起摸鱼吗 🐟",
        "刚升级了新版本", "快捷键 yyds", "晚上还要开会 😮‍💨", "有没有人在做毕设",
    ]

    func signInWithApple(idToken: String, nonce: String) async throws { isSignedIn = true }
    func signOut() async { isSignedIn = false }
    func fetchProfile() async throws -> UserProfile? { profile }
    func saveProfile(_ profile: UserProfile) async throws { self.profile = profile }

    func join(room: String, anonymous: Bool, profile: UserProfile?) async throws -> [ChatMessage] {
        await leave()
        self.room = room
        self.profile = profile ?? self.profile
        let count = Int.random(in: 3...9)
        members = Self.names.shuffled().prefix(count).map {
            RoomMember(id: UUID().uuidString, presence: .init(displayName: $0, avatarURL: nil, isAnonymous: $0.hasPrefix("匿名"), isAway: Bool.random() && Bool.random()))
        }
        me = RoomMember(id: "me", presence: presence(anonymous: anonymous, away: false))
        publishMembers()

        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        let now = Date()
        return (0..<8).map { i in
            fakeMessage(at: now.addingTimeInterval(Double(i - 8) * 40))
        }
        .filter { !blockedNames.contains($0.displayName) }
        .map { var m = $0; m.isReplay = true; return m }
    }

    func setAway(_ away: Bool) async {
        guard var me else { return }
        me = RoomMember(id: me.id, presence: .init(displayName: me.presence.displayName, avatarURL: me.presence.avatarURL, isAnonymous: me.presence.isAnonymous, isAway: away))
        self.me = me
        publishMembers()
    }

    func setAnonymous(_ anonymous: Bool, profile: UserProfile?) async {
        guard let me else { return }
        self.me = RoomMember(id: me.id, presence: presence(anonymous: anonymous, away: me.presence.isAway))
        publishMembers()
    }

    func leave() async {
        timer?.invalidate()
        timer = nil
        room = nil
        members = []
        me = nil
    }

    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage {
        guard let room else { throw ChatError.invalid }
        var m = ChatMessage(
            id: UUID(), room: room, body: body, isAnonymous: anonymous,
            displayName: presence(anonymous: anonymous, away: false).displayName,
            avatarURL: nil, authorID: anonymous ? nil : profile?.id, authorKey: "me", createdAt: Date())
        m.isMine = true
        return m
    }

    func report(messageID: UUID, reason: ReportReason) async throws {}

    func blockAuthor(of message: ChatMessage) async throws {
        blockedNames.insert(message.displayName)
        blocks.append(BlockedUser(id: UUID(), label: message.displayName, createdAt: Date()))
    }

    func listBlocks() async throws -> [BlockedUser] { blocks }

    func unblock(_ id: UUID) async throws {
        if let b = blocks.first(where: { $0.id == id }) { blockedNames.remove(b.label) }
        blocks.removeAll { $0.id == id }
    }

    // MARK: -

    private func presence(anonymous: Bool, away: Bool) -> PresencePayload {
        PresencePayload(
            displayName: anonymous ? "匿名 · 企鹅·7b2" : (profile?.displayName ?? "我"),
            avatarURL: anonymous ? nil : profile?.avatarURL,
            isAnonymous: anonymous, isAway: away)
    }

    private func publishMembers() {
        onEvent?(.members(members + (me.map { [$0] } ?? [])))
    }

    private func tick() {
        guard room != nil else { return }
        if Double.random(in: 0...1) < 0.7 {
            let m = fakeMessage(at: Date())
            if !blockedNames.contains(m.displayName) { onEvent?(.message(m)) }
        }
        if Double.random(in: 0...1) < 0.05, members.count > 1 {
            members.removeLast()
            publishMembers()
        } else if Double.random(in: 0...1) < 0.05, let name = Self.names.randomElement() {
            members.append(RoomMember(id: UUID().uuidString, presence: .init(displayName: name, avatarURL: nil, isAnonymous: name.hasPrefix("匿名"), isAway: false)))
            publishMembers()
        }
    }

    private func fakeMessage(at date: Date) -> ChatMessage {
        let name = (members.randomElement()?.presence.displayName) ?? Self.names.randomElement()!
        return ChatMessage(
            id: UUID(), room: room ?? "", body: Self.lines.randomElement()!, isAnonymous: name.hasPrefix("匿名"),
            displayName: name, avatarURL: nil, authorID: nil, authorKey: name, createdAt: date)
    }
}
