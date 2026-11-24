import GoofCore
import SwiftUI

/// The floating panel's content: the expanded panel or the collapsed capsule.
struct PanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.panelCollapsed {
                PanelCapsule()
            } else {
                ExpandedPanel()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private let panelShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

struct PanelBackground: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.isSnapshot {
                Color(red: 0.13, green: 0.135, blue: 0.16).opacity(0.94)
            } else {
                VisualEffectBackground(material: .hudWindow)
            }
            // "Background strength" from the dashboard: more tint, more contrast.
            Color(red: 0.07, green: 0.075, blue: 0.09).opacity(model.settings.panelOpacity * 0.6)
        }
    }
}

private struct ExpandedPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            DanmakuArea()
            PanelComposer()
        }
        .background { PanelBackground() }
        .clipShape(panelShape)
        .overlay { panelShape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .overlay(alignment: .bottomTrailing) {
            if !model.isSnapshot {
                WindowResizeGrip()
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .help("Drag to resize")
            }
        }
    }
}

// MARK: - Header

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                AppTile(app: model.currentApp, size: 16)
                Text(model.currentApp?.name ?? "Goof")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if model.isDemo { DemoTag() }
                if model.isAway { AwayBadge() }
                Spacer(minLength: 4)
                Label {
                    Text("\(model.onlineCount)").monospacedDigit()
                } icon: {
                    Image(systemName: "person.2.fill").font(.system(size: 9))
                }
                .labelStyle(CompactLabelStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .accessibilityLabel("\(model.onlineCount) online")
            }
            .contentShape(Rectangle())
            .overlay { if !model.isSnapshot { WindowDragArea(toolTip: "Drag to move the panel") } }

            let next: DanmakuStyle = model.settings.danmakuStyle == .scroll ? .stack : .scroll
            HeaderButton(symbol: next.symbol, help: "Switch to \(next.title)") {
                model.setStyle(next)
            }
            HeaderButton(symbol: "chevron.down", help: "Collapse into a capsule") {
                model.setCollapsed(true)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

struct DemoTag: View {
    var body: some View {
        Text("Demo")
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.45))
            .background(Capsule().fill(Color(red: 1, green: 0.65, blue: 0.14).opacity(0.18)))
            .help("No server connected. The people and messages are simulated on this Mac")
    }
}

private struct AwayBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = model.graceRemaining(at: context.date).map { Int($0.rounded(.up)) }
            Text(seconds.map { "Away · \($0)s" } ?? "Away")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color(red: 0.96, green: 0.65, blue: 0.14))
                .help("You switched to another app. You'll leave the room when the grace period ends, unless you come back")
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.62))
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Danmaku

private struct DanmakuArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.feed
        ZStack {
            switch feed.style {
            case .scroll:
                ScrollStyleView()
            case .stack:
                DanmakuStackView()
            }
            if feed.isEmpty {
                EmptyRoomHint()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { feed.resize(width: proxy.size.width, height: proxy.size.height) }
                    .onChange(of: proxy.size) { _, size in feed.resize(width: size.width, height: size.height) }
            }
        }
        .background {
            if !model.isSnapshot { HoverTracker { feed.setHovering($0) } }
        }
        .overlay(alignment: .bottomTrailing) {
            if feed.isPaused, feed.waitingCount > 0 {
                Text("Paused · \(feed.waitingCount) new")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: feed.isPaused)
    }
}

private struct ScrollStyleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.feed
        if model.isSnapshot {
            FrozenDanmakuLayer(items: feed.items, fontSize: feed.fontSize.points, laneHeight: feed.laneHeight,
                               now: feed.pausedAt ?? Date())
        } else {
            DanmakuScrollLayer(items: feed.items, fontSize: feed.fontSize.points, laneHeight: feed.laneHeight,
                               paused: feed.isPaused) { message in
                MessageMenu.make(for: message, model: model)
            }
        }
    }
}

private struct EmptyRoomHint: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.isJoining ? "Joining the room…" : "It's quiet in here. Say the first word!")
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.42))
            .allowsHitTesting(false)
    }
}

// MARK: - Composer

private struct PanelComposer: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let notice = model.notice {
                NoticeLine(notice: notice)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 7) {
                IdentityButton()
                TextField("", text: $model.draft, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.36)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { model.send() }
                    .onKeyPress(.escape) {
                        // Esc first cancels an input method's composition.
                        if FieldEditor.hasMarkedText { return .ignored }
                        focused = false
                        model.returnFocus()
                        return .handled
                    }
                    .disabled(!model.isInRoom)
                    .accessibilityLabel("Send")
                let remaining = MessageRules.maxLength - model.draft.count
                if remaining < 20 {
                    Text("\(remaining)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(remaining < 0 ? Color(red: 1, green: 0.42, blue: 0.42) : .white.opacity(0.5))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.14))
        .animation(.easeOut(duration: 0.18), value: model.notice)
        .onChange(of: model.composerFocusRequest) { _, _ in focused = true }
    }

    private var placeholder: String {
        if model.isAway { return "Away. Go back to the app to keep chatting" }
        return model.postsAnonymously ? "Say something anonymously…" : "Say something as \(model.profile.profile.displayName)…"
    }
}

private struct IdentityButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let anonymous = model.postsAnonymously
        Button {
            model.setPostAnonymously(!anonymous)
        } label: {
            Group {
                if anonymous {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(GoofColors.accent)
                } else {
                    AvatarView(image: model.profile.avatar, name: model.profile.profile.displayName,
                               accent: Color(hex: model.profile.profile.accentHex) ?? GoofColors.accent, size: 17)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anonymous ? "Posting anonymously (click to post as yourself)" : "Posting as yourself (click to post anonymously)")
        .accessibilityLabel(anonymous ? "Post anonymously" : "Post as yourself")
    }
}

private struct NoticeLine: View {
    @Environment(AppModel.self) private var model
    let notice: AppModel.Notice

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: notice.isWarning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10.5))
            Text(notice.text)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let action = notice.action {
                Button(action.title) { model.perform(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GoofColors.accent)
            }
        }
        .foregroundStyle(notice.isWarning ? Color(red: 0.96, green: 0.65, blue: 0.14) : .white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.top, 5)
    }
}

// MARK: - Capsule

private struct PanelCapsule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            AppTile(app: model.currentApp, size: 15)
            Text(model.currentApp?.name ?? "Goof")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.unreadCount > 0 {
                Text(model.unreadCount > 99 ? "99+" : "\(model.unreadCount)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(GoofColors.accent))
                    .foregroundStyle(.white)
                    .help("\(model.unreadCount) new since you collapsed the panel")
            }
            Image(systemName: "person.2.fill").font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.62))
            Text("\(model.onlineCount)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground() }
        .clipShape(Capsule())
        .overlay { CapsuleOutline().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .overlay {
            if !model.isSnapshot {
                WindowDragArea(toolTip: "Click to expand, drag to move") { model.setCollapsed(false) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.setCollapsed(false) }
    }
}

/// A capsule built from two arcs. Stroking `Capsule()` itself drew short
/// straight lines just outside its round ends in offscreen renders.
private struct CapsuleOutline: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.midY), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.midY), radius: radius,
                    startAngle: .degrees(270), endAngle: .degrees(450), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> CapsuleOutline {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
