import AppKit
import KuroCore
import Observation

/// App-wide state and the single place where settings changes get applied.
@Observable
@MainActor
final class AppModel {
    struct Notice: Equatable {
        enum Action: Equatable {
            case openProfile
            case openApps

            var title: String {
                switch self {
                case .openProfile: "去设置"
                case .openApps: "打开 Dashboard"
                }
            }
        }

        let id = UUID()
        let text: String
        var isWarning = true
        var action: Action?
    }

    let settings: SettingsStore
    let profile: ProfileStore
    let feed: DanmakuFeed
    let chat: ChatService
    /// True while rendering screenshots: no system hooks, no live effects.
    let isSnapshot: Bool

    // Room
    private(set) var status: RoomResolver.Status = .none
    private(set) var pendingRoomID: String?
    private(set) var frontmostCatalogID: String?
    private(set) var members: [RoomMember] = []
    private(set) var isJoining = false
    private(set) var joinedRoom: String?

    // Panel
    var draft = ""
    private(set) var notice: Notice?
    private(set) var panelCollapsed: Bool
    private(set) var unreadCount = 0
    /// Incremented to ask the composer to take keyboard focus.
    private(set) var composerFocusRequest = 0

    // Dashboard
    var dashboardPane: DashboardPane = .apps
    private(set) var blocked: [BlockedUser] = []
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginMessage: String?
    private(set) var hotKeyProblem: String?

    @ObservationIgnored private var monitor: ActivityMonitor?
    @ObservationIgnored private var panel: FloatingPanelController?
    @ObservationIgnored private var dashboard: DashboardWindowController?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var limiter = SendRateLimiter()
    @ObservationIgnored private var lastOperation: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var pauseTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var blockedKeys: Set<String> = []
    /// Author keys of the user's own messages in the joined room, learned from `send`.
    @ObservationIgnored private var myAuthorKeys: Set<String> = []
    @ObservationIgnored private var joinRetry: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(chat: ChatService? = nil, settings: SettingsStore? = nil, profile: ProfileStore? = nil,
         feed: DanmakuFeed? = nil, isSnapshot: Bool = false) {
        let settings = settings ?? SettingsStore()
        self.settings = settings
        self.profile = profile ?? ProfileStore()
        self.feed = feed ?? DanmakuFeed()
        self.chat = chat ?? ChatServiceFactory.make()
        self.isSnapshot = isSnapshot
        panelCollapsed = settings.panelCollapsed

        self.feed.setStyle(settings.danmakuStyle)
        self.feed.setSpeed(settings.danmakuSpeed)
        self.feed.setFontSize(settings.fontSize)
        self.chat.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Hooks into the system. Called once at launch (not for snapshots).
    func start() {
        guard !started, !isSnapshot else { return }
        started = true

        if let until = settings.pausedUntil, until <= Date() { settings.pausedUntil = nil }

        let panel = FloatingPanelController(model: self)
        panel.apply(hideWhenSharing: settings.hideWhenSharing)
        panel.setCollapsed(panelCollapsed, animated: false)
        self.panel = panel

        let monitor = ActivityMonitor(allowed: effectiveAllowedApps, idleThreshold: settings.idleThreshold)
        monitor.onStatusChange = { [weak self] status in self?.statusChanged(status) }
        monitor.onSignalsChange = { [weak self] in self?.signalsChanged() }
        self.monitor = monitor
        monitor.start()
        signalsChanged()

        schedulePauseEnd()
        // Timers do not run while the Mac sleeps; re-check a pause that ended overnight.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePauseEnd() }
        }

        applyHotKey()
        refreshLaunchAtLogin()
        enqueue { [chat, profile] in try? await chat.updateProfile(profile.publicProfile) }
        Task { await refreshBlocked() }

        if !settings.hasCompletedOnboarding {
            showDashboard()
        }
    }

    // MARK: - Derived state

    var isDemo: Bool { chat.kind == .demo }
    var currentApp: CatalogApp? { status.roomID.flatMap(AppCatalog.app(id:)) }
    var isInRoom: Bool { status.roomID != nil }
    var isAway: Bool {
        if case .away = status { return true }
        return false
    }
    var onlineCount: Int { members.filter { !$0.isAway }.count }
    var isPaused: Bool { settings.pausedUntil.map { $0 > Date() } ?? false }

    /// Anonymous when the user chose it, or when there is no nickname to show.
    var postsAnonymously: Bool { settings.postAnonymously || !profile.hasNickname }

    /// A catalog app in front that the user has not turned on yet.
    var frontmostDisabledApp: CatalogApp? {
        guard let id = frontmostCatalogID, !settings.allowedApps.contains(id) else { return nil }
        return AppCatalog.app(id: id)
    }

    var pendingApp: CatalogApp? { pendingRoomID.flatMap(AppCatalog.app(id:)) }

    func graceRemaining(at date: Date) -> TimeInterval? {
        monitor?.graceRemaining(at: date)
    }

    /// One line for the menu bar menu and the dashboard sidebar.
    var statusSummary: String {
        if isPaused { return pauseUntilText.map { "Kuro 已暂停，\($0)恢复" } ?? "Kuro 已暂停" }
        if let app = currentApp {
            return isAway ? "\(app.name) 房间 · 离开中" : "\(app.name) 房间 · \(onlineCount) 人在线"
        }
        if let app = pendingApp { return "正在进入 \(app.name) 房间…" }
        if settings.allowedApps.isEmpty { return "还没有开启任何应用" }
        if let app = frontmostDisabledApp { return "\(app.name) 还没开启弹幕" }
        return "当前应用没有房间"
    }

    /// "18:30 " or "明天 09:00 ", nil when paused until resumed.
    var pauseUntilText: String? {
        guard let until = settings.pausedUntil, until != .distantFuture else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: until)
        return Calendar.current.isDateInToday(until) ? "\(time) " : "明天 \(time) "
    }

    var menuBarSymbol: String {
        if isPaused { return "moon.zzz.fill" }
        if isAway { return "bubble.left.and.bubble.right" }
        return isInRoom ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
    }

    // MARK: - Apps and presence

    func setApp(_ id: String, allowed: Bool) {
        if allowed { settings.allowedApps.insert(id) } else { settings.allowedApps.remove(id) }
        monitor?.setAllowed(effectiveAllowedApps)
    }

    func setApps(_ ids: [String], allowed: Bool) {
        if allowed { settings.allowedApps.formUnion(ids) } else { settings.allowedApps.subtract(ids) }
        monitor?.setAllowed(effectiveAllowedApps)
    }

    func pause(_ duration: PauseDuration) {
        settings.pausedUntil = duration.endDate(from: Date())
        monitor?.setAllowed(effectiveAllowedApps)
        schedulePauseEnd()
    }

    func resume() {
        settings.pausedUntil = nil
        monitor?.setAllowed(effectiveAllowedApps)
        schedulePauseEnd()
    }

    func setIdleMinutes(_ minutes: Int) {
        settings.idleMinutes = minutes
        monitor?.setIdleThreshold(settings.idleThreshold)
    }

    private var effectiveAllowedApps: Set<String> { isPaused ? [] : settings.allowedApps }

    private func schedulePauseEnd() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard let until = settings.pausedUntil else { return }
        if until <= Date() { return resume() }
        guard until != .distantFuture else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    // MARK: - Panel

    func setPanelEnabled(_ enabled: Bool) {
        settings.panelEnabled = enabled
        updatePanel()
    }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != panelCollapsed else { return }
        panelCollapsed = collapsed
        settings.panelCollapsed = collapsed
        if !collapsed { unreadCount = 0 }
        panel?.setCollapsed(collapsed, animated: true)
    }

    func setStyle(_ style: DanmakuStyle) {
        settings.danmakuStyle = style
        feed.setStyle(style)
    }

    func setSpeed(_ speed: Double) {
        settings.danmakuSpeed = speed
        feed.setSpeed(speed)
    }

    func setFontSize(_ size: DanmakuFontSize) {
        settings.fontSize = size
        feed.setFontSize(size)
    }

    func setHideWhenSharing(_ hide: Bool) {
        settings.hideWhenSharing = hide
        panel?.apply(hideWhenSharing: hide)
    }

    func resetPanelPosition() {
        panel?.resetPosition()
        if panelCollapsed { setCollapsed(false) }
        if isInRoom, !settings.panelEnabled { setPanelEnabled(true) }
    }

    /// The global shortcut: put the cursor in the composer without leaving the app you are in.
    func focusComposer() {
        guard isInRoom, !isSnapshot else {
            NSSound.beep()
            return
        }
        if !settings.panelEnabled { setPanelEnabled(true) }
        if panelCollapsed { setCollapsed(false) }
        panel?.focus()
        composerFocusRequest += 1
    }

    func returnFocus() {
        panel?.returnFocus()
    }

    private func updatePanel() {
        panel?.setVisible(settings.panelEnabled && isInRoom)
        panel?.setDimmed(isAway)
    }

    // MARK: - Messages

    func send() {
        guard isInRoom else { return show(ChatError.notInRoom) }
        let text: String
        switch MessageRules.validate(draft) {
        case .failure(.empty): return
        case .failure(.tooLong(let limit)): return show(ChatError.tooLong(limit: limit))
        case .success(let value): text = value
        }
        let now = Date()
        switch limiter.check(text, at: now) {
        case .allowed: break
        case .duplicate: return show(ChatError.duplicate)
        case .tooFast: return show(ChatError.rateLimited)
        }
        limiter.record(text, at: now)
        draft = ""
        let anonymous = postsAnonymously
        Task {
            do {
                var sent = try await chat.send(text, anonymous: anonymous)
                guard sent.room == joinedRoom else { return }
                sent.isMine = true
                myAuthorKeys.insert(sent.authorKey)
                if feed.contains(messageID: sent.id) {
                    // The server's broadcast of this message got here first.
                    feed.markMine(messageID: sent.id)
                } else {
                    feed.push(sent)
                }
            } catch {
                if draft.isEmpty { draft = text }
                show(error)
            }
        }
    }

    func report(_ message: ChatMessage, reason: ReportReason) {
        feed.remove(messageID: message.id)
        Task {
            do {
                try await chat.report(message, reason: reason)
                show(info: "已举报，感谢反馈")
            } catch {
                show(error)
            }
        }
    }

    func block(_ message: ChatMessage) {
        guard !message.isMine else { return }
        blockedKeys.insert(message.authorKey)
        feed.removeAll { $0.authorKey == message.authorKey }
        Task {
            do {
                try await chat.block(authorOf: message)
                await refreshBlocked()
                show(info: "已屏蔽「\(message.displayName)」，可以在 Dashboard 里解除")
            } catch {
                show(error)
            }
        }
    }

    func unblock(_ user: BlockedUser) {
        Task {
            do {
                try await chat.unblock(user)
                blocked.removeAll { $0.id == user.id }
                blockedKeys = []
            } catch {
                show(error)
            }
        }
    }

    func copy(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.body, forType: .string)
    }

    private func refreshBlocked() async {
        if let list = try? await chat.blockedUsers() { blocked = list }
    }

    // MARK: - Identity and profile

    func setPostAnonymously(_ anonymous: Bool) {
        if !anonymous, !profile.hasNickname {
            return show(Notice(text: "先设置一个昵称，才能实名发言", action: .openProfile))
        }
        let before = postsAnonymously
        settings.postAnonymously = anonymous
        syncAnonymity(from: before)
    }

    func saveProfile(_ newValue: LocalProfile) {
        let before = postsAnonymously
        profile.save(newValue)
        publishProfile()
        syncAnonymity(from: before)
    }

    func setAvatar(from url: URL) throws {
        try profile.setAvatar(from: url)
        publishProfile()
    }

    func removeAvatar() {
        profile.removeAvatar()
        publishProfile()
    }

    private func publishProfile() {
        let snapshot = profile.publicProfile
        enqueue { [chat] in
            do { try await chat.updateProfile(snapshot) } catch { self.show(error) }
        }
    }

    private func syncAnonymity(from before: Bool) {
        let now = postsAnonymously
        guard now != before, isInRoom else { return }
        enqueue { [chat] in await chat.setAnonymous(now) }
    }

    // MARK: - Launch at login and shortcut

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = LaunchAtLogin.set(enabled)
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isEnabled
        if LaunchAtLogin.needsApproval {
            launchAtLoginMessage = "需要在「系统设置 › 通用 › 登录项」里允许 Kuro"
        }
    }

    func setHotKeyEnabled(_ enabled: Bool) {
        settings.hotKeyEnabled = enabled
        applyHotKey()
    }

    private func applyHotKey() {
        hotKey = nil
        hotKeyProblem = nil
        guard settings.hotKeyEnabled, !isSnapshot else { return }
        do {
            hotKey = try GlobalHotKey(.composeShortcut) { [weak self] in self?.focusComposer() }
        } catch {
            hotKeyProblem = "这个快捷键被其他应用占用了"
        }
    }

    // MARK: - Dashboard

    func showDashboard(_ pane: DashboardPane? = nil) {
        if let pane { dashboardPane = pane }
        if dashboard == nil { dashboard = DashboardWindowController(model: self) }
        AppIconCache.refresh()
        refreshLaunchAtLogin()
        // The list may have been unavailable at launch (offline, not signed in yet).
        Task { await refreshBlocked() }
        dashboard?.show()
    }

    func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        dashboard?.close()
    }

    func restartOnboarding() {
        settings.hasCompletedOnboarding = false
        showDashboard()
    }

    func perform(_ action: Notice.Action) {
        switch action {
        case .openProfile: showDashboard(.profile)
        case .openApps: showDashboard(.apps)
        }
    }

    // MARK: - Room lifecycle

    private func statusChanged(_ new: RoomResolver.Status) {
        let wasAway = isAway
        status = new
        switch new {
        case .none:
            if joinedRoom != nil { leaveRoom() }
        case .active(let room), .away(let room):
            if room != joinedRoom {
                join(room)
            } else if isAway != wasAway {
                let away = isAway
                enqueue { [chat] in await chat.setAway(away) }
            }
        }
        signalsChanged()
        updatePanel()
    }

    private func signalsChanged() {
        pendingRoomID = monitor?.pendingRoom?.roomID
        frontmostCatalogID = monitor?.frontmostCatalogID
    }

    /// - Parameter attempt: 0 for a new room, then counts retries after errors.
    private func join(_ room: String, attempt: Int = 0) {
        joinRetry?.cancel()
        joinRetry = nil
        if attempt == 0 {
            joinedRoom = room
            members = []
            unreadCount = 0
            myAuthorKeys = []
            feed.clear()
        }
        isJoining = true
        let replay = settings.replayHistory
        enqueue { [weak self] in
            guard let self, self.joinedRoom == room else { return }
            do {
                let history = try await self.chat.join(room: room, anonymous: self.postsAnonymously)
                guard self.joinedRoom == room else { return }
                self.isJoining = false
                if replay {
                    let visible = history.filter { !self.blockedKeys.contains($0.authorKey) }
                    self.feed.replay(visible.map { self.markingMine($0) })
                }
                if self.isAway { await self.chat.setAway(true) }
            } catch {
                guard self.joinedRoom == room else { return }
                if attempt == 0 { self.show(error) }
                guard Self.shouldRetryJoin(after: error) else {
                    self.isJoining = false
                    return
                }
                // Offline, server restarting, Wi-Fi not back after sleep: keep
                // trying while the user is still in this app, backing off to 30 s.
                let delay = min(30, 2 << min(attempt, 4))
                self.joinRetry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self, self.joinedRoom == room else { return }
                    self.join(room, attempt: attempt + 1)
                }
            }
        }
    }

    /// Errors that describe the user's situation (banned, needs a nickname...)
    /// will not go away by retrying; anything else may be the network.
    private static func shouldRetryJoin(after error: Error) -> Bool {
        guard let chatError = error as? ChatError else { return true }
        if case .server = chatError { return true }
        return false
    }

    private func markingMine(_ message: ChatMessage) -> ChatMessage {
        guard !message.isMine, myAuthorKeys.contains(message.authorKey) else { return message }
        var message = message
        message.isMine = true
        return message
    }

    private func leaveRoom() {
        joinRetry?.cancel()
        joinRetry = nil
        joinedRoom = nil
        members = []
        isJoining = false
        unreadCount = 0
        feed.clear()
        enqueue { [chat] in await chat.leave() }
    }

    private func handle(_ event: ChatEvent) {
        switch event {
        case .message(let incoming):
            guard incoming.room == joinedRoom, !blockedKeys.contains(incoming.authorKey) else { return }
            let message = markingMine(incoming)
            feed.push(message)
            if panelCollapsed, !message.isMine { unreadCount += 1 }
        case .hide(let id):
            feed.remove(messageID: id)
        case .members(let list):
            members = list
        }
    }

    /// Runs backend calls one after another, so a quick leave-then-join can
    /// never reach the server in the wrong order.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = lastOperation
        lastOperation = Task {
            await previous?.value
            await operation()
        }
    }

    // MARK: - Notices

    func show(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        var notice = Notice(text: text)
        if (error as? ChatError) == .needsNickname { notice.action = .openProfile }
        show(notice)
    }

    func show(info text: String) {
        show(Notice(text: text, isWarning: false))
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(notice.action == nil ? 3 : 6))
            guard !Task.isCancelled else { return }
            if self.notice?.id == notice.id { self.notice = nil }
        }
    }

    // MARK: - Snapshots

    /// Puts the model in a fixed state for screenshots.
    func applySnapshot(room: String, members: [RoomMember], messages: [ChatMessage], style: DanmakuStyle,
                       panelSize: CGSize, collapsed: Bool = false, unread: Int = 0) {
        status = .active(roomID: room)
        joinedRoom = room
        self.members = members
        panelCollapsed = collapsed
        unreadCount = unread
        feed.setStyle(style)
        feed.freezeForSnapshot(messages, panelWidth: panelSize.width, height: panelSize.height - 30 - 1 - 34)
    }
}

enum DashboardPane: String, CaseIterable, Identifiable {
    case apps, profile, appearance, privacy, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "应用"
        case .profile: "个人资料"
        case .appearance: "弹幕外观"
        case .privacy: "隐私与安全"
        case .general: "通用"
        }
    }

    var subtitle: String {
        switch self {
        case .apps: "选择哪些应用会让你进入房间"
        case .profile: "像直播账号一样，别人在弹幕里看到的你"
        case .appearance: "面板里的弹幕怎么显示，改动会立刻生效"
        case .privacy: "匿名、在线判定和屏蔽列表"
        case .general: "启动、快捷键和关于 Kuro"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2.fill"
        case .profile: "person.fill"
        case .appearance: "text.bubble.fill"
        case .privacy: "hand.raised.fill"
        case .general: "gearshape.fill"
        }
    }

    var tint: String {
        switch self {
        case .apps: "#3A86FF"
        case .profile: "#FF5A5F"
        case .appearance: "#8338EC"
        case .privacy: "#2FBF71"
        case .general: "#8A8F9D"
        }
    }
}
