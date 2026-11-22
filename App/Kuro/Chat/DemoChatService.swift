import Foundation
import KuroCore

/// Offline backend: simulated people chatting in every room. Kuro uses it
/// whenever no server is configured, so the app is fully usable out of the box,
/// and the UI marks everything as a demo.
@MainActor
final class DemoChatService: ChatService {
    var onEvent: ((ChatEvent) -> Void)?
    let kind: BackendKind = .demo

    private var room: String?
    private var anonymous = true
    private var away = false
    private var profile: PublicProfile?
    private var members: [RoomMember] = []
    private var blocked: [String: BlockedUser] = [:]   // authorKey -> entry
    private var timer: Timer?
    private var rng: SeededGenerator
    private let liveTicks: Bool

    /// - Parameters:
    ///   - seed: fixed seed for reproducible output (snapshots); random otherwise.
    ///   - liveTicks: false keeps the room quiet (snapshots, tests).
    init(seed: UInt64? = nil, liveTicks: Bool = true) {
        rng = SeededGenerator(seed: seed ?? UInt64.random(in: 1...UInt64.max))
        self.liveTicks = liveTicks
    }

    func updateProfile(_ profile: PublicProfile) async throws {
        self.profile = profile
        publishMembers()
    }

    func join(room: String, anonymous: Bool) async throws -> [ChatMessage] {
        await leave()
        self.room = room
        self.anonymous = anonymous
        self.away = false

        let crowd = Self.crowdSize(for: room)
        members = (0..<crowd).map { i in
            let person = Self.people[i % Self.people.count]
            return RoomMember(id: "demo-\(room)-\(i)", displayName: person.name, isAnonymous: person.name.hasPrefix("匿名"),
                              isAway: i % 9 == 4)
        }
        publishMembers()

        if liveTicks {
            let timer = Timer(timeInterval: 1.3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        let now = Date()
        return (0..<7).compactMap { i -> ChatMessage? in
            var message = makeMessage(at: now.addingTimeInterval(Double(i - 7) * 50))
            message.isReplay = true
            return blocked[message.authorKey] == nil ? message : nil
        }
    }

    func setAway(_ away: Bool) async {
        self.away = away
        publishMembers()
    }

    func setAnonymous(_ anonymous: Bool) async {
        self.anonymous = anonymous
        publishMembers()
    }

    func leave() async {
        timer?.invalidate()
        timer = nil
        room = nil
        members = []
    }

    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage {
        guard let room else { throw ChatError.notInRoom }
        var message = ChatMessage(
            id: UUID(), room: room, body: body, isAnonymous: anonymous,
            displayName: anonymous ? myAlias(in: room) : (profile?.displayName ?? ""),
            accentHex: anonymous ? nil : profile?.accentHex, avatarURL: nil,
            authorKey: "me", createdAt: Date())
        message.isMine = true

        // Someone in the room sometimes answers, like a real livestream.
        if liveTicks, Double.random(in: 0...1, using: &rng) < 0.45 {
            let delay = Double.random(in: 1.2...2.8, using: &rng)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.reply(in: room) }
            }
        }
        return message
    }

    func report(_ message: ChatMessage, reason: ReportReason) async throws {
        // A server would record the report and hide the message once enough people report it.
    }

    func block(authorOf message: ChatMessage) async throws {
        guard !message.isMine else { return }
        blocked[message.authorKey] = BlockedUser(id: UUID(), label: message.displayName, createdAt: Date())
    }

    func blockedUsers() async throws -> [BlockedUser] {
        blocked.values.sorted { $0.createdAt > $1.createdAt }
    }

    func unblock(_ user: BlockedUser) async throws {
        blocked = blocked.filter { $0.value.id != user.id }
    }

    // MARK: - Simulation

    private func tick() {
        guard let room else { return }
        if Double.random(in: 0...1, using: &rng) < 0.72 {
            let message = makeMessage(at: Date())
            if blocked[message.authorKey] == nil, message.room == room { onEvent?(.message(message)) }
        }
        let roll = Double.random(in: 0...1, using: &rng)
        if roll < 0.06, members.count > 3 {
            members.remove(at: Int.random(in: 0..<members.count, using: &rng))
            publishMembers()
        } else if roll > 0.94 {
            let person = Self.people.randomElement(using: &rng)!
            members.append(RoomMember(id: UUID().uuidString, displayName: person.name, isAnonymous: person.name.hasPrefix("匿名"), isAway: false))
            publishMembers()
        }
    }

    private func reply(in room: String) {
        guard self.room == room else { return }
        let person = Self.people.randomElement(using: &rng)!
        let body = Self.replies.randomElement(using: &rng)!
        let message = ChatMessage(id: UUID(), room: room, body: body, isAnonymous: person.name.hasPrefix("匿名"),
                                  displayName: person.name, accentHex: person.accent, avatarURL: nil,
                                  authorKey: person.name, createdAt: Date())
        if blocked[message.authorKey] == nil { onEvent?(.message(message)) }
    }

    private func makeMessage(at date: Date) -> ChatMessage {
        let room = room ?? ""
        let person = Self.people.randomElement(using: &rng)!
        let lines = Self.lines(for: room)
        return ChatMessage(id: UUID(), room: room, body: lines.randomElement(using: &rng)!,
                           isAnonymous: person.name.hasPrefix("匿名"), displayName: person.name,
                           accentHex: person.name.hasPrefix("匿名") ? nil : person.accent, avatarURL: nil,
                           authorKey: person.name, createdAt: date)
    }

    private func publishMembers() {
        guard let room else { return }
        let name = anonymous ? myAlias(in: room) : (profile?.displayName ?? "我")
        let me = RoomMember(id: "me", displayName: name, isAnonymous: anonymous, isAway: away)
        onEvent?(.members(members + [me]))
    }

    private func myAlias(in room: String) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return AnonymousAlias.make(seed: "me|\(room)|\(day)")
    }

    // MARK: - Content

    private struct Person { let name: String; let accent: String }

    private static let people: [Person] = [
        .init(name: "阿柚", accent: "#FF7A85"), .init(name: "Momo", accent: "#FFB347"),
        .init(name: "小林", accent: "#5AC8FA"), .init(name: "debug 侠", accent: "#7CD992"),
        .init(name: "像素猫", accent: "#C792EA"), .init(name: "Leo", accent: "#FF9F1C"),
        .init(name: "夜猫子", accent: "#8AB4FF"), .init(name: "Kiki", accent: "#FF6FB5"),
        .init(name: "Rin", accent: "#4FD1C5"), .init(name: "豆豆", accent: "#F6C453"),
        .init(name: "匿名 · 水獭·a3f", accent: "#9AA0AE"), .init(name: "匿名 · 柴犬·19c", accent: "#9AA0AE"),
        .init(name: "匿名 · 狐狸·5e0", accent: "#9AA0AE"), .init(name: "匿名 · 鲸鱼·c71", accent: "#9AA0AE"),
    ]

    private static let replies = ["哈哈哈同感", "+1", "真的！", "我也是我也是", "握手 🤝", "说得对", "顶一下", "加油加油"]

    private static let common = ["大家好～", "今天第三杯咖啡了", "有人一起摸鱼吗 🐟", "下班前再冲一会", "晚上还要开会 😮‍💨",
                                 "终于搞定了！！", "这个房间好热闹", "周五了冲鸭", "刚升级了新版本", "有没有人在做毕设"]

    private static let byRoom: [String: [String]] = [
        "claude": ["有人也在让 Claude 改简历吗", "Artifacts 真的好用", "这个回答太长了哈哈", "求一个好用的 prompt",
                   "我在让它帮我翻译合同", "深夜还在和 AI 聊天的举个手", "它居然看懂了我的草图"],
        "chatgpt": ["今天的回答有点啰嗦", "语音模式好像变快了", "在用它查资料", "有人用它写周报吗"],
        "figma": ["Auto Layout 又把我整懵了", "有人推荐一个好看的配色吗", "甲方说再大一点 😮‍💨", "组件库终于整理完了",
                  "Dev Mode 有人在用吗", "这个渐变好难调", "今天画了 30 个图标"],
        "vscode": ["TypeScript 报错报到怀疑人生", "这个插件 yyds", "CI 又挂了", "终于跑通了！！", "谁在写 Rust", "格式化快捷键是啥来着"],
        "cursor": ["Tab 补全今天特别懂我", "让它重构了整个文件", "有人在用 Agent 模式吗", "规则文件写好效率翻倍"],
        "xcode": ["Preview 又崩了", "SwiftUI 动画调了一下午", "Archive 终于过了", "签名问题谁懂啊", "模拟器好慢"],
        "terminal": ["git rebase 搞乱了救命", "有人用 tmux 吗", "zsh 主题求推荐", "rm -rf 之前一定要看清楚"],
        "notion": ["周报写完的举手", "数据库视图好好用", "有人分享一下读书模板吗", "今天的待办清空了 ✨"],
        "obsidian": ["双链笔记越写越多", "有人用 Canvas 吗", "插件装太多了卡"],
    ]

    private static let byCategory: [CatalogApp.Category: [String]] = [
        .ai: ["今天又学到新东西了", "AI 写的代码我还得改", "这个模型更新好快"],
        .code: ["编译通过了但是不对", "代码评审被打回来了", "有人一起结对吗", "这个 bug 我找了两小时"],
        .design: ["对齐像素强迫症犯了", "字体选了半天", "这一版甲方应该会满意吧"],
        .office: ["表格公式写不出来", "PPT 还差最后几页", "在赶季度报告"],
        .creative: ["渲染还要 40 分钟", "这段剪了一下午", "混音调不好", "导出又失败了"],
    ]

    private static func lines(for room: String) -> [String] {
        var lines = common
        if let specific = byRoom[room] { lines += specific + specific }
        if let category = AppCatalog.app(id: room)?.category, let extra = byCategory[category] { lines += extra }
        return lines
    }

    /// A believable, stable crowd size per room.
    private static func crowdSize(for room: String) -> Int {
        let popular: [String: Int] = ["claude": 128, "vscode": 213, "figma": 46, "cursor": 87, "chatgpt": 152, "xcode": 39, "notion": 37]
        if let n = popular[room] { return n }
        return 8 + Int(StableHash.fnv1a(room) % 40)
    }
}

/// SplitMix64, so demo output can be made reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
