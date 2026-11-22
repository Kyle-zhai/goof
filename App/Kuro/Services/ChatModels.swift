import Foundation

struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let room: String
    let body: String
    let isAnonymous: Bool
    let displayName: String
    let avatarURL: URL?
    /// Nil for anonymous messages: the server never reveals who wrote them.
    let authorID: UUID?
    /// Per-room, per-day opaque key used to filter blocked authors.
    let authorKey: String
    let createdAt: Date
    /// True for history shown on join, rendered in a quieter style.
    var isReplay = false
    var isMine = false

    enum CodingKeys: String, CodingKey {
        case id, room, body
        case isAnonymous = "is_anonymous"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case authorID = "author_id"
        case authorKey = "author_key"
        case createdAt = "created_at"
    }
}

/// What each client publishes into a room's presence. Never contains the app
/// name (the room already is the app) or, when anonymous, the account id.
struct PresencePayload: Codable, Equatable, Sendable {
    var displayName: String
    var avatarURL: URL?
    var isAnonymous: Bool
    var isAway: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case isAnonymous = "is_anonymous"
        case isAway = "is_away"
    }
}

struct RoomMember: Identifiable, Hashable, Sendable {
    let id: String
    let presence: PresencePayload

    static func == (a: RoomMember, b: RoomMember) -> Bool { a.id == b.id && a.presence == b.presence }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct UserProfile: Codable, Equatable, Sendable {
    var id: UUID
    var username: String
    var displayName: String
    var avatarURL: URL?
    var bio: String
    var accentColor: String
    var defaultAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, bio
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case accentColor = "accent_color"
        case defaultAnonymous = "default_anonymous"
    }
}

struct BlockedUser: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let label: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, label
        case createdAt = "created_at"
    }
}

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, abuse, sexual, hate, privacy, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: return "垃圾广告 / 刷屏"
        case .abuse: return "辱骂 / 骚扰"
        case .sexual: return "色情内容"
        case .hate: return "仇恨言论"
        case .privacy: return "泄露隐私"
        case .other: return "其他"
        }
    }
}

enum ChatEvent: Sendable {
    case message(ChatMessage)
    case hide(UUID)
    case members([RoomMember])
}

enum ChatError: LocalizedError, Equatable {
    case notSignedIn
    case profileRequired
    case rateLimited
    case duplicate
    case accountTooNew
    case banned
    case blockedContent
    case invalid
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "请先登录"
        case .profileRequired: return "请先在 Dashboard 里设置个人资料"
        case .rateLimited: return "发得太快了，歇一下"
        case .duplicate: return "不要重复刷屏哦"
        case .accountTooNew: return "新账号注册 10 分钟后才能发言"
        case .banned: return "你的账号已被限制发言"
        case .blockedContent: return "内容包含不允许的词"
        case .invalid: return "消息无效"
        case .other(let s): return s
        }
    }

    /// Maps the error codes raised by the SQL functions in supabase/migrations.
    init(serverMessage: String) {
        switch true {
        case serverMessage.contains("not_authenticated"): self = .notSignedIn
        case serverMessage.contains("profile_required"): self = .profileRequired
        case serverMessage.contains("rate_limited"): self = .rateLimited
        case serverMessage.contains("duplicate"): self = .duplicate
        case serverMessage.contains("account_too_new"): self = .accountTooNew
        case serverMessage.contains("banned"): self = .banned
        case serverMessage.contains("blocked_content"): self = .blockedContent
        case serverMessage.contains("invalid_"): self = .invalid
        default: self = .other(serverMessage)
        }
    }
}

/// The backend seen by the app. `SupabaseChatService` is the real one;
/// `MockChatService` runs fully offline for UI work and demos.
@MainActor
protocol ChatService: AnyObject {
    var onEvent: ((ChatEvent) -> Void)? { get set }
    var isSignedIn: Bool { get }
    var currentUserID: UUID? { get }
    var isOffline: Bool { get }

    func signInWithApple(idToken: String, nonce: String) async throws
    func signOut() async
    func fetchProfile() async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) async throws

    /// Joins a room and returns the short replay history.
    func join(room: String, anonymous: Bool, profile: UserProfile?) async throws -> [ChatMessage]
    func setAway(_ away: Bool) async
    func setAnonymous(_ anonymous: Bool, profile: UserProfile?) async
    func leave() async

    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage
    func report(messageID: UUID, reason: ReportReason) async throws
    func blockAuthor(of message: ChatMessage) async throws
    func listBlocks() async throws -> [BlockedUser]
    func unblock(_ id: UUID) async throws
}

enum WireCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            for f in [fractional, plain] { if let date = f.date(from: s) { return date } }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
}
