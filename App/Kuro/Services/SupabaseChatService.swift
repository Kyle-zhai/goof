import Foundation
import Supabase

/// Real backend. See supabase/migrations for the server side: every write goes
/// through a security-definer RPC, and new messages arrive as broadcasts on the
/// private `room:<bundle id>` channel.
@MainActor
final class SupabaseChatService: ChatService {
    var onEvent: ((ChatEvent) -> Void)?
    let isOffline = false

    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var room: String?
    private var members: [String: RoomMember] = [:]
    private var blockedKeys: Set<String> = []
    private var presence: PresencePayload?
    /// Random per launch so presence can't be tied to an account.
    private let presenceKey = UUID().uuidString

    init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    var isSignedIn: Bool { client.auth.currentUser != nil }
    var currentUserID: UUID? { client.auth.currentUser?.id }

    // MARK: Account

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func signOut() async {
        await leave()
        try? await client.auth.signOut()
    }

    func fetchProfile() async throws -> UserProfile? {
        guard let uid = client.auth.currentUser?.id else { return nil }
        let response = try await client.from("profiles").select().eq("id", value: uid).limit(1).execute()
        return try WireCoding.decoder.decode([UserProfile].self, from: response.data).first
    }

    func saveProfile(_ profile: UserProfile) async throws {
        try await client.from("profiles").upsert(profile).execute()
    }

    // MARK: Room

    func join(room: String, anonymous: Bool, profile: UserProfile?) async throws -> [ChatMessage] {
        guard isSignedIn else { throw ChatError.notSignedIn }
        await leave()
        self.room = room

        let key = presenceKey
        let channel = client.channel("room:\(room)") { config in
            config.isPrivate = true
            config.presence.key = key
        }
        let messages = channel.broadcastStream(event: "message")
        let hides = channel.broadcastStream(event: "hide")
        let presenceChanges = channel.presenceChange()

        streamTasks = [
            Task { [weak self] in
                for await raw in messages { self?.handleMessage(raw) }
            },
            Task { [weak self] in
                for await raw in hides {
                    if let obj = Self.payload(of: raw), case let .string(id)? = obj["id"], let uuid = UUID(uuidString: id) {
                        self?.onEvent?(.hide(uuid))
                    }
                }
            },
            Task { [weak self] in
                for await action in presenceChanges { self?.handlePresence(action) }
            },
        ]

        try await channel.subscribeWithError()
        self.channel = channel

        let keys = try await rpc("blocked_keys", ["p_room": room], as: [String].self)
        blockedKeys = Set(keys)
        presence = try await makePresence(anonymous: anonymous, profile: profile, away: false)
        if let presence { try await channel.track(presence) }

        var history = try await rpc("recent_messages", ["p_room": room], as: [ChatMessage].self)
        history = history.filter { !blockedKeys.contains($0.authorKey) }
        for i in history.indices { history[i].isReplay = true }
        return history
    }

    func setAway(_ away: Bool) async {
        guard var presence, let channel, presence.isAway != away else { return }
        presence.isAway = away
        self.presence = presence
        try? await channel.track(presence)
    }

    func setAnonymous(_ anonymous: Bool, profile: UserProfile?) async {
        guard let channel, let current = presence else { return }
        guard let next = try? await makePresence(anonymous: anonymous, profile: profile, away: current.isAway) else { return }
        presence = next
        try? await channel.track(next)
    }

    func leave() async {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        if let channel {
            await channel.untrack()
            await client.removeChannel(channel)
        }
        channel = nil
        room = nil
        presence = nil
        members = [:]
    }

    // MARK: Messages

    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage {
        guard let room else { throw ChatError.invalid }
        struct Params: Encodable, Sendable { let p_room: String; let p_body: String; let p_anonymous: Bool }
        var message = try await rpc("send_message", Params(p_room: room, p_body: body, p_anonymous: anonymous), as: ChatMessage.self)
        message.isMine = true
        return message
    }

    func report(messageID: UUID, reason: ReportReason) async throws {
        struct Params: Encodable, Sendable { let p_message_id: UUID; let p_reason: String }
        try await rpcVoid("report_message", Params(p_message_id: messageID, p_reason: reason.rawValue))
    }

    func blockAuthor(of message: ChatMessage) async throws {
        try await rpcVoid("block_message_author", ["p_message_id": message.id.uuidString])
        blockedKeys.insert(message.authorKey)
    }

    func listBlocks() async throws -> [BlockedUser] {
        let response = try await mapErrors { try await self.client.rpc("list_blocks").execute() }
        return try WireCoding.decoder.decode([BlockedUser].self, from: response.data)
    }

    func unblock(_ id: UUID) async throws {
        try await rpcVoid("unblock", ["p_block_id": id.uuidString])
        if let room {
            let keys = try await rpc("blocked_keys", ["p_room": room], as: [String].self)
            blockedKeys = Set(keys)
        }
    }

    // MARK: - Helpers

    private func makePresence(anonymous: Bool, profile: UserProfile?, away: Bool) async throws -> PresencePayload {
        if anonymous || profile == nil, let room {
            let alias = try await rpc("my_anon_name", ["p_room": room], as: String.self)
            return PresencePayload(displayName: alias, avatarURL: nil, isAnonymous: true, isAway: away)
        }
        return PresencePayload(displayName: profile?.displayName ?? "", avatarURL: profile?.avatarURL, isAnonymous: false, isAway: away)
    }

    private func handleMessage(_ raw: JSONObject) {
        guard let obj = Self.payload(of: raw), let message = try? Self.decode(ChatMessage.self, from: obj) else { return }
        guard message.room == room, !blockedKeys.contains(message.authorKey) else { return }
        onEvent?(.message(message))
    }

    private func handlePresence(_ action: any PresenceAction) {
        for key in action.leaves.keys { members[key] = nil }
        for (key, value) in action.joins {
            if let p = try? Self.decode(PresencePayload.self, from: value.state) {
                members[key] = RoomMember(id: key, presence: p)
            }
        }
        onEvent?(.members(Array(members.values)))
    }

    /// Broadcasts arrive wrapped as {type, event, payload}; unwrap if needed.
    private nonisolated static func payload(of raw: JSONObject) -> JSONObject? {
        if case let .object(inner)? = raw["payload"] { return inner }
        return raw
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from obj: JSONObject) throws -> T {
        try WireCoding.decoder.decode(T.self, from: JSONEncoder().encode(obj))
    }

    private func rpc<T: Decodable>(_ fn: String, _ params: some Encodable & Sendable, as: T.Type) async throws -> T {
        let response = try await mapErrors { try await self.client.rpc(fn, params: params).execute() }
        return try WireCoding.decoder.decode(T.self, from: response.data)
    }

    private func rpcVoid(_ fn: String, _ params: some Encodable & Sendable) async throws {
        _ = try await mapErrors { try await self.client.rpc(fn, params: params).execute() }
    }

    private func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw ChatError(serverMessage: error.message)
        }
    }
}
