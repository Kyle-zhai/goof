import AppKit
import KuroCore
import SwiftUI

/// `Kuro --snapshot` renders the panel, dashboard and onboarding to PNGs and
/// quits. CI uses it to check the UI on a real Mac; the README screenshots
/// come from it too. Nothing here runs in normal use.
@MainActor
enum SnapshotRenderer {
    static var isRequested: Bool { CommandLine.arguments.contains("--snapshot") }

    static func run() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KuroSnapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let model = makeModel()
        let panelSize = CGSize(width: 340, height: 220)
        let room = "claude"

        for style in DanmakuStyle.allCases {
            model.applySnapshot(room: room, members: members(128), messages: messages(room: room), style: style,
                                panelSize: panelSize)
            render(OnDesktop(size: panelSize) { PanelView() }, model: model, name: "panel-\(style.rawValue)",
                   into: directory, appearance: .darkAqua)
        }

        model.applySnapshot(room: room, members: members(128), messages: [], style: .scroll,
                            panelSize: panelSize, collapsed: true, unread: 12)
        render(OnDesktop(size: FloatingPanelController.collapsedSize) { PanelView() }, model: model, name: "panel-capsule",
               into: directory, appearance: .darkAqua)

        model.applySnapshot(room: room, members: members(128), messages: messages(room: room), style: .scroll,
                            panelSize: panelSize)
        let dashboardSize = CGSize(width: DashboardWindowController.size.width, height: DashboardWindowController.size.height)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for pane in DashboardPane.allCases {
                model.dashboardPane = pane
                let suffix = appearance == .darkAqua ? "-dark" : ""
                render(DashboardRoot(), model: model, size: dashboardSize, name: "dashboard-\(pane.rawValue)\(suffix)",
                       into: directory, appearance: appearance)
            }
        }

        model.settings.hasCompletedOnboarding = false
        for step in 0..<3 {
            render(OnboardingView(step: step).frame(minWidth: 780, minHeight: 540).tint(KuroColors.accent), model: model,
                   size: dashboardSize, name: "onboarding-\(step + 1)", into: directory, appearance: .aqua)
        }

        print("KURO_SNAPSHOTS=\(directory.path)")
        fflush(stdout)
        exit(0)
    }

    // MARK: - Fixture

    private static func makeModel() -> AppModel {
        let suite = "app.kuro.snapshots"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.allowedApps = ["claude", "figma", "vscode", "cursor", "notion", "xcode"]
        settings.hasCompletedOnboarding = true
        settings.postAnonymously = true

        let profileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("KuroSnapshotProfile", isDirectory: true)
        try? FileManager.default.removeItem(at: profileDirectory)
        let profile = ProfileStore(defaults: defaults, directory: profileDirectory)
        profile.save(LocalProfile(username: "ayou", displayName: "阿柚", bio: "白天画图标，晚上写 Swift", accentHex: "#FF5A5F"))

        return AppModel(chat: DemoChatService(seed: 7, liveTicks: false), settings: settings, profile: profile,
                        feed: DanmakuFeed(startsTimer: false), isSnapshot: true)
    }

    private static func members(_ count: Int) -> [RoomMember] {
        (0..<count).map { RoomMember(id: "m\($0)", displayName: "m\($0)", isAnonymous: $0 % 3 == 0, isAway: $0 % 11 == 5) }
    }

    private static func messages(room: String) -> [ChatMessage] {
        let lines: [(String, String?, String, Bool, Bool)] = [
            ("阿柚", "#FF7A85", "有人也在让 Claude 改简历吗", false, true),
            ("Momo", "#FFB347", "Artifacts 真的好用", false, true),
            ("匿名 · 水獭·a3f", nil, "深夜还在和 AI 聊天的举个手 🙋", false, false),
            ("小林", "#5AC8FA", "它居然看懂了我的草图", false, false),
            ("debug 侠", "#7CD992", "这个回答太长了哈哈", false, false),
            ("像素猫", "#C792EA", "求一个好用的 prompt", false, false),
            ("匿名 · 橘猫·3f2", nil, "大家好～第一次来", true, false),
            ("Leo", "#FF9F1C", "欢迎欢迎", false, false),
            ("Kiki", "#FF6FB5", "我在让它帮我翻译合同", false, false),
            ("夜猫子", "#8AB4FF", "+1", false, false),
        ]
        let start = Date().addingTimeInterval(-60)
        return lines.enumerated().map { index, line in
            let (name, accent, body, mine, replay) = line
            return ChatMessage(id: UUID(), room: room, body: body, isAnonymous: name.hasPrefix("匿名"), displayName: name,
                               accentHex: accent, avatarURL: nil, authorKey: name,
                               createdAt: start.addingTimeInterval(Double(index) * 5), isReplay: replay, isMine: mine)
        }
    }

    // MARK: - Rendering

    private static func render<V: View>(_ view: V, model: AppModel, size: CGSize? = nil, name: String, into directory: URL,
                                        appearance: NSAppearance.Name) {
        let root = view.environment(model)
        let host = NSHostingView(rootView: root)
        let fitting = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: fitting)
        host.appearance = NSAppearance(named: appearance)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))

        // Let SwiftUI lay out, load images and run onAppear.
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        host.display()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fitting.width * scale),
                                         pixelsHigh: Int(fitting.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = fitting
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.close()
    }
}

/// A piece of desktop wallpaper behind the panel, so the translucent panel
/// looks like it does on screen.
private struct OnDesktop<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            .padding(28)
            .background {
                LinearGradient(colors: [Color(red: 0.23, green: 0.27, blue: 0.47), Color(red: 0.42, green: 0.25, blue: 0.43),
                                        Color(red: 0.86, green: 0.45, blue: 0.4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
    }
}
