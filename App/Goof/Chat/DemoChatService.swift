import Foundation
import GoofCore

/// Offline backend: simulated people chatting in every room. Goof uses it
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
            return RoomMember(id: "demo-\(room)-\(i)", displayName: person.name, isAnonymous: AnonymousAlias.isAlias(person.name),
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
            members.append(RoomMember(id: UUID().uuidString, displayName: person.name, isAnonymous: AnonymousAlias.isAlias(person.name), isAway: false))
            publishMembers()
        }
    }

    private func reply(in room: String) {
        guard self.room == room else { return }
        let person = Self.people.randomElement(using: &rng)!
        let body = Self.replies.randomElement(using: &rng)!
        let message = ChatMessage(id: UUID(), room: room, body: body, isAnonymous: AnonymousAlias.isAlias(person.name),
                                  displayName: person.name, accentHex: person.accent, avatarURL: nil,
                                  authorKey: person.name, createdAt: Date())
        if blocked[message.authorKey] == nil { onEvent?(.message(message)) }
    }

    private func makeMessage(at date: Date) -> ChatMessage {
        let room = room ?? ""
        let person = Self.people.randomElement(using: &rng)!
        let lines = Self.lines(for: room)
        return ChatMessage(id: UUID(), room: room, body: lines.randomElement(using: &rng)!,
                           isAnonymous: AnonymousAlias.isAlias(person.name), displayName: person.name,
                           accentHex: AnonymousAlias.isAlias(person.name) ? nil : person.accent, avatarURL: nil,
                           authorKey: person.name, createdAt: date)
    }

    private func publishMembers() {
        guard let room else { return }
        let name = anonymous ? myAlias(in: room) : (profile?.displayName ?? "Me")
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
        .init(name: "Yuzu", accent: "#FF7A85"), .init(name: "Momo", accent: "#FFB347"),
        .init(name: "Kai", accent: "#5AC8FA"), .init(name: "bugzapper", accent: "#7CD992"),
        .init(name: "PixelCat", accent: "#C792EA"), .init(name: "Leo", accent: "#FF9F1C"),
        .init(name: "nightowl", accent: "#8AB4FF"), .init(name: "Kiki", accent: "#FF6FB5"),
        .init(name: "Rin", accent: "#4FD1C5"), .init(name: "Bean", accent: "#F6C453"),
        .init(name: "Anon Otter·a3f", accent: "#9AA0AE"), .init(name: "Anon Shiba·19c", accent: "#9AA0AE"),
        .init(name: "Anon Fox·5e0", accent: "#9AA0AE"), .init(name: "Anon Whale·c71", accent: "#9AA0AE"),
    ]

    private static let replies = ["haha same", "+1", "Right?!", "Me too", "🤝", "So true", "This ↑", "You got this"]

    private static let common = ["Hi everyone!", "Coffee number three today", "Anyone else procrastinating? 🙃",
                                 "One more push before I log off", "Another meeting tonight 😮‍💨", "Finally done!!",
                                 "Busy room today", "Friday, let's go", "Just updated to the new version",
                                 "Anyone working on their thesis?"]

    private static let byRoom: [String: [String]] = [
        "claude": ["Anyone else getting Claude to fix their résumé?", "Artifacts are so good", "That answer was way too long lol",
                   "Anyone got a good prompt?", "Having it translate a contract", "Who else is chatting with AI at 2am",
                   "It actually got my sketch"],
        "chatgpt": ["Answers are a bit wordy today", "Voice mode feels faster", "Using it for research",
                    "Anyone use it for status reports?"],
        "figma": ["Auto Layout got me again", "Any good color palette ideas?", "Client says make it bigger 😮‍💨",
                  "Finally cleaned up the component library", "Anyone using Dev Mode?", "This gradient is so hard to get right",
                  "Drew 30 icons today"],
        "vscode": ["These TypeScript errors are breaking me", "This extension is the best", "CI is red again",
                   "It finally works!!", "Who's writing Rust?", "What's the format shortcut again?"],
        "cursor": ["Tab completion really gets me today", "Had it refactor the whole file", "Anyone using Agent mode?",
                   "A good rules file doubles your speed"],
        "xcode": ["Previews crashed again", "Spent all afternoon on one SwiftUI animation", "Archive finally passed",
                  "Who actually understands code signing?", "The simulator is so slow"],
        "terminal": ["Messed up a git rebase, help", "Anyone use tmux?", "zsh theme recommendations?",
                     "Always look twice before rm -rf"],
        "notion": ["Hands up if your weekly report is done", "Database views are so handy",
                   "Anyone want to share a reading template?", "Cleared my to-do list ✨"],
        "obsidian": ["My linked notes keep growing", "Anyone using Canvas?", "Too many plugins, it's getting slow"],
    ]

    private static let byCategory: [CatalogApp.Category: [String]] = [
        .ai: ["Learned something new again today", "I still have to fix the code it writes", "These models update so fast"],
        .code: ["It compiles but it's wrong", "Code review sent it back", "Anyone up for pairing?", "Two hours on this bug so far"],
        .design: ["Nudging pixels again", "Took forever to pick a font", "The client should like this version"],
        .office: ["Can't get this spreadsheet formula right", "A few more slides to go", "Rushing the quarterly report"],
        .creative: ["40 more minutes of rendering", "Spent all afternoon on this cut", "Can't get the mix right", "Export failed again"],
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
