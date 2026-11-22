import SwiftUI

/// Danmaku scroll right-to-left, only inside the panel.
struct DanmakuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: model.feed.items.isEmpty)) { context in
                ZStack(alignment: .topLeading) {
                    ForEach(model.feed.items) { item in
                        DanmakuBubble(item: item)
                            .offset(x: x(for: item, width: geo.size.width, now: context.date),
                                    y: Double(item.lane) * DanmakuFeed.laneHeight + 4)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .onAppear { resize(geo.size) }
            .onChange(of: geo.size) { _, size in resize(size) }
        }
        .clipped()
        .overlay {
            if model.feed.items.isEmpty {
                Text(model.chat.isOffline ? "离线演示模式 · 弹幕会自动出现" : "还没人说话，来发第一条吧")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func resize(_ size: CGSize) {
        model.feed.resize(width: Double(size.width), height: Double(size.height) - 8)
    }

    private func x(for item: DanmakuItem, width: Double, now: Date) -> Double {
        let elapsed = now.timeIntervalSince(item.start)
        let distance = width + item.width
        return width - distance * min(1, elapsed / item.duration)
    }
}

private struct DanmakuBubble: View {
    @Environment(AppModel.self) private var model
    let item: DanmakuItem

    var body: some View {
        let m = item.message
        HStack(spacing: 4) {
            Text(m.displayName)
                .font(Font(DanmakuFeed.nameFont))
                .foregroundStyle(m.isAnonymous ? Color.secondary : Color.accentColor)
            Text(m.body)
                .font(Font(DanmakuFeed.font))
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background {
            if m.isMine {
                Capsule().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
            }
        }
        .opacity(m.isReplay ? 0.55 : 1)
        .contextMenu {
            if !m.isMine {
                Menu("举报") {
                    ForEach(ReportReason.allCases) { reason in
                        Button(reason.title) { model.report(m, reason: reason) }
                    }
                }
                Button("屏蔽此人") { model.block(m) }
            }
            Button("复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(m.body, forType: .string)
            }
        }
    }
}
