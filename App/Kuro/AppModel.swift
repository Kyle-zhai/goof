import AppKit
import KuroCore
import Observation

@Observable
@MainActor
final class AppModel {
    let settings = SettingsStore()
    let feed = DanmakuFeed()
    let chat: ChatService

    private(set) var status: RoomResolver.Status = .none
    private(set) var joinedRoom: String?
    private(set) var members: [RoomMember] = []
    private(set) var profile: UserProfile?
    private(set) var isSignedIn = false
    private(set) var blocks: [BlockedUser] = []
    var draft = ""
    var notice: String?
    var panelCollapsed = false {
        didSet { panel?.setCollapsed(panelCollapsed) }
    }

    @ObservationIgnored private var monitor: ActivityMonitor!
    @ObservationIgnored private var panel: FloatingPanelController?
    @ObservationIgnored private var limiter = SendRateLimiter()
    @ObservationIgnored private var joinTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init() {
        if let config = BackendConfig.fromBundle() {
            chat = SupabaseChatService(url: config.url, anonKey: config.anonKey)
        } else {
            chat = MockChatService()
        }
        feed.speed = settings.danmakuSpeed

        monitor = ActivityMonitor(allowed: settings.effectiveAllowedApps,
                                  idleThreshold: TimeInterval(settings.idleThresholdMinutes * 60))
        chat.onEvent = { [weak self] in self?.handle($0) }
        monitor.onStatusChange = { [weak self] in self?.statusChanged($0) }
        panel = FloatingPanelController(model: self)
        monitor.start()

        Task { await refreshProfile() }
    }

    // MARK: Derived

    var currentApp: CatalogApp? { status.roomID.flatMap(AppCatalog.app(for:)) }
    var onlineCount: Int { members.filter { !$0.presence.isAway }.count }
    var isAway: Bool { if case .away = status { return true } else { return false } }
    var menuBarSymbol: String {
        if settings.paused { return "moon.zzz" }
        return status.roomID == nil ? "bubble.left" : "bubble.left.and.bubble.right.fill"
    }

    // MARK: Settings changes (called from the dashboard)

    func setApp(_ bundleID: String, allowed: Bool) {
        if allowed { settings.allowedApps.insert(bundleID) } else { settings.allowedApps.remove(bundleID) }
        monitor.setAllowed(settings.effectiveAllowedApps)
    }

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        monitor.setAllowed(settings.effectiveAllowedApps)
    }

    func setIdleThreshold(minutes: Int) {
        settings.idleThresholdMinutes = minutes
        monitor.setIdleThreshold(TimeInterval(minutes * 60))
    }

    func setPanelEnabled(_ enabled: Bool) {
        settings.panelEnabled = enabled
        updatePanelVisibility()
    }

    func setSpeed(_ speed: Double) {
        settings.danmakuSpeed = speed
        feed.speed = speed
    }

    func setPostAnonymously(_ anonymous: Bool) {
        settings.postAnonymously = anonymous
        Task { await chat.setAnonymous(anonymous, profile: profile) }
    }

    // MARK: Account

    func refreshProfile() async {
        isSignedIn = chat.isSignedIn
        profile = try? await chat.fetchProfile()
        blocks = (try? await chat.listBlocks()) ?? []
    }

    func signInWithApple(idToken: String, nonce: String) async {
        do {
            try await chat.signInWithApple(idToken: idToken, nonce: nonce)
            await refreshProfile()
            if let room = joinedRoom { rejoin(room) }
        } catch {
            show(error)
        }
    }

    func signOut() async {
        await chat.signOut()
        isSignedIn = false
        profile = nil
        joinedRoom = nil
        members = []
        feed.clear()
    }

    func saveProfile(_ profile: UserProfile) async -> Bool {
        do {
            try await chat.saveProfile(profile)
            self.profile = profile
            await chat.setAnonymous(settings.postAnonymously, profile: profile)
            return true
        } catch {
            show(error)
            return false
        }
    }

    // MARK: Chat

    func send() {
        let text: String
        switch MessageRules.validate(draft) {
        case .failure(.empty): return
        case .failure(.tooLong(let limit)): return show(message: "最多 \(limit) 个字")
        case .success(let t): text = t
        }
        switch limiter.check(text, at: Date()) {
        case .allowed: break
        case .duplicate: return show(ChatError.duplicate)
        case .tooFast: return show(ChatError.rateLimited)
        }
        limiter.record(text, at: Date())
        draft = ""
        let anonymous = settings.postAnonymously
        Task {
            do {
                let sent = try await chat.send(text, anonymous: anonymous)
                feed.remove(messageID: sent.id) // in case the broadcast won the race
                feed.push(sent)
            } catch {
                show(error)
            }
        }
    }

    func report(_ message: ChatMessage, reason: ReportReason) {
        Task {
            do {
                try await chat.report(messageID: message.id, reason: reason)
                feed.remove(messageID: message.id)
                show(message: "已举报，感谢反馈")
            } catch { show(error) }
        }
    }

    func block(_ message: ChatMessage) {
        Task {
            do {
                try await chat.blockAuthor(of: message)
                feed.removeAll { $0.authorKey == message.authorKey }
                blocks = (try? await chat.listBlocks()) ?? blocks
                show(message: "已屏蔽 \(message.displayName)")
            } catch { show(error) }
        }
    }

    func unblock(_ block: BlockedUser) {
        Task {
            do {
                try await chat.unblock(block.id)
                blocks.removeAll { $0.id == block.id }
            } catch { show(error) }
        }
    }

    // MARK: - Private

    private func statusChanged(_ new: RoomResolver.Status) {
        status = new
        switch new {
        case .none:
            leaveRoom()
        case .active(let room), .away(let room):
            if room != joinedRoom { rejoin(room) }
            let away = isAway
            Task { await chat.setAway(away) }
        }
        updatePanelVisibility()
    }

    private func rejoin(_ room: String) {
        joinTask?.cancel()
        joinedRoom = room
        members = []
        feed.clear()
        let anonymous = settings.postAnonymously
        let profile = profile
        joinTask = Task {
            do {
                let history = try await chat.join(room: room, anonymous: anonymous, profile: profile)
                guard !Task.isCancelled, joinedRoom == room else { return }
                feed.replay(history)
            } catch {
                guard !Task.isCancelled else { return }
                show(error)
            }
        }
    }

    private func leaveRoom() {
        joinTask?.cancel()
        joinedRoom = nil
        members = []
        feed.clear()
        Task { await chat.leave() }
    }

    private func handle(_ event: ChatEvent) {
        switch event {
        case .message(let m): feed.push(m)
        case .hide(let id): feed.remove(messageID: id)
        case .members(let list): members = list
        }
    }

    private func updatePanelVisibility() {
        let visible = settings.panelEnabled && status.roomID != nil
        panel?.setVisible(visible)
    }

    private func show(_ error: Error) {
        show(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    private func show(message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }
}

struct BackendConfig {
    let url: URL
    let anonKey: String

    /// Reads values injected into Info.plist from Config.xcconfig. Missing or
    /// empty values mean "run offline with the mock backend".
    static func fromBundle(_ bundle: Bundle = .main) -> BackendConfig? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "KuroSupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "KuroSupabaseAnonKey") as? String,
              !urlString.isEmpty, !key.isEmpty,
              let url = URL(string: urlString) else { return nil }
        return BackendConfig(url: url, anonKey: key)
    }
}
