import KuroCore
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
                    .help("拖动调整大小")
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
                Text(model.currentApp?.name ?? "Kuro")
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
                .accessibilityLabel("\(model.onlineCount) 人在线")
            }
            .contentShape(Rectangle())
            .overlay { if !model.isSnapshot { WindowDragArea(toolTip: "拖动移动面板") } }

            let next: DanmakuStyle = model.settings.danmakuStyle == .scroll ? .stack : .scroll
            HeaderButton(symbol: next.symbol, help: "切换为\(next.title)") {
                model.setStyle(next)
            }
            HeaderButton(symbol: "chevron.down", help: "收起成小胶囊") {
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
        Text("演示")
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.45))
            .background(Capsule().fill(Color(red: 1, green: 0.65, blue: 0.14).opacity(0.18)))
            .help("没有连接服务器，房间里的人和消息是本地模拟的")
    }
}

private struct AwayBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = model.graceRemaining(at: context.date).map { Int($0.rounded(.up)) }
            Text(seconds.map { "离开中 · \($0)s" } ?? "离开中")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color(red: 0.96, green: 0.65, blue: 0.14))
                .help("你切到了别的应用，宽限期结束后会退出房间；回来就继续")
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
                Text("已暂停 · \(feed.waitingCount) 条新弹幕")
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
        Text(model.isJoining ? "正在进入房间…" : "还没人说话，来发第一条吧")
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
                    .accessibilityLabel("发弹幕")
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
        if model.isAway { return "离开中，回到应用里就能接着聊" }
        return model.postsAnonymously ? "匿名发条弹幕…" : "以「\(model.profile.profile.displayName)」发条弹幕…"
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
                        .foregroundStyle(KuroColors.accent)
                } else {
                    AvatarView(image: model.profile.avatar, name: model.profile.profile.displayName,
                               accent: Color(hex: model.profile.profile.accentHex) ?? KuroColors.accent, size: 17)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anonymous ? "匿名发送中（点击切换为实名）" : "实名发送中（点击切换为匿名）")
        .accessibilityLabel(anonymous ? "匿名发送" : "实名发送")
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
                    .foregroundStyle(KuroColors.accent)
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
            Text(model.currentApp?.name ?? "Kuro")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.unreadCount > 0 {
                Text(model.unreadCount > 99 ? "99+" : "\(model.unreadCount)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(KuroColors.accent))
                    .foregroundStyle(.white)
                    .help("收起后来了 \(model.unreadCount) 条新弹幕")
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
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .overlay {
            if !model.isSnapshot {
                WindowDragArea(toolTip: "点击展开，拖动移动") { model.setCollapsed(false) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.setCollapsed(false) }
    }
}
