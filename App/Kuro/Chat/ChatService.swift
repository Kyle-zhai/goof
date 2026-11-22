import Foundation

// MARK: - Backend contract
//
// Kuro ships without a server. `ChatService` is the seam where one plugs in:
// implement it against your own backend (Supabase, Firebase, a WebSocket
// server...) and return it from `ChatServiceFactory.make()`. Until then the app
// runs on `DemoChatService`, which simulates a room locally.
// docs/BACKEND.md describes what a real backend must guarantee.

/// What the UI tells people about where messages come from.
enum BackendKind: Equatable, Sendable {
    /// Simulated people and messages. The UI labels everything as a demo.
    case demo
    /// A real server, with a short name shown in settings.
    case server(name: String)
}

@MainActor
protocol ChatService: AnyObject {
    /// Live events for the joined room. Set by `AppModel`; call on the main actor.
    var onEvent: ((ChatEvent) -> Void)? { get set }
    var kind: BackendKind { get }

    /// The public profile changed (also called once at launch).
    func updateProfile(_ profile: PublicProfile) async throws

    /// Joins a room and returns a short replay of recent messages, oldest first.
    /// Joining a new room implicitly leaves the previous one.
    func join(room: String, anonymous: Bool) async throws -> [ChatMessage]
    /// The user is still in the room but not using the app right now.
    func setAway(_ away: Bool) async
    /// Switches how the user appears in the room's presence.
    func setAnonymous(_ anonymous: Bool) async
    func leave() async

    /// Sends a message to the joined room and returns it as others will see it.
    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage
    func report(_ message: ChatMessage, reason: ReportReason) async throws
    /// Hides the author of `message` from now on, anonymous or not.
    func block(authorOf message: ChatMessage) async throws
    func blockedUsers() async throws -> [BlockedUser]
    func unblock(_ user: BlockedUser) async throws
}

enum ChatServiceFactory {
    /// Replace with your own implementation to connect Kuro to a server.
    @MainActor
    static func make() -> ChatService {
        DemoChatService()
    }
}

// MARK: - Models

struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let room: String
    let body: String
    let isAnonymous: Bool
    /// The profile name, or a per-room per-day alias such as "匿名 · 橘猫·3f2".
    let displayName: String
    /// Name color chosen by the author (hex). Nil for anonymous messages.
    let accentHex: String?
    let avatarURL: URL?
    /// Opaque, stable per author within a room and day. Lets clients hide a
    /// blocked author without ever learning who an anonymous author is.
    let authorKey: String
    let createdAt: Date
    /// History shown on join, rendered in a quieter style. Not sent by servers.
    var isReplay = false
    /// Written by this user. Not sent by servers.
    var isMine = false

    enum CodingKeys: String, CodingKey {
        case id, room, body
        case isAnonymous = "is_anonymous"
        case displayName = "display_name"
        case accentHex = "accent_hex"
        case avatarURL = "avatar_url"
        case authorKey = "author_key"
        case createdAt = "created_at"
    }
}

/// The part of the local profile a backend may publish.
struct PublicProfile: Equatable, Sendable {
    var username: String
    var displayName: String
    var bio: String
    var accentHex: String
    /// 256×256 PNG, or nil for the generated initial avatar.
    var avatarPNG: Data?
}

/// One person in the room, as presence reports them. Never includes which
/// other apps they use, and for anonymous people never an account id.
struct RoomMember: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    var isAnonymous: Bool
    var isAway: Bool
}

struct BlockedUser: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    /// What the user saw when they blocked, e.g. "匿名 · 橘猫·3f2".
    let label: String
    let createdAt: Date
}

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, abuse, sexual, hate, privacy, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "垃圾广告 / 刷屏"
        case .abuse: "辱骂 / 骚扰"
        case .sexual: "色情内容"
        case .hate: "仇恨言论"
        case .privacy: "泄露隐私"
        case .other: "其他"
        }
    }
}

enum ChatEvent: Sendable {
    case message(ChatMessage)
    /// A message was removed by moderation.
    case hide(UUID)
    case members([RoomMember])
}

enum ChatError: LocalizedError, Equatable {
    case rateLimited
    case duplicate
    case tooLong(limit: Int)
    case notInRoom
    case needsNickname
    case banned
    case server(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited: "发得太快了，歇一下"
        case .duplicate: "不要重复刷屏哦"
        case .tooLong(let limit): "最多 \(limit) 个字"
        case .notInRoom: "当前不在任何房间"
        case .needsNickname: "先在 Dashboard 里设置昵称，才能实名发言"
        case .banned: "你的账号已被限制发言"
        case .server(let message): message
        }
    }
}
