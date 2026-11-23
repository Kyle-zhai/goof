import SwiftUI

/// The tidy style: messages line up from the bottom and older ones fade out
/// at the top. No scrolling, so it never steals the pointer from the app below.
struct DanmakuStackView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let feed = model.feed
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(feed.rows) { message in
                    StackRow(message: message, fontSize: feed.fontSize.points)
                        .contextMenu { MessageContextMenu(message: message) }
                        .transition(.asymmetric(insertion: .offset(y: 10).combined(with: .opacity), removal: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .clipped()
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.34)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct StackRow: View {
    let message: ChatMessage
    let fontSize: CGFloat

    var body: some View {
        let name = Text(message.displayName)
            .font(.system(size: fontSize - 1, weight: .semibold))
            .foregroundStyle(NameColor.color(for: message))
        let text = Text(message.body)
            .font(.system(size: fontSize - 0.5))
            .foregroundStyle(Color.white.opacity(0.95))
        Text("\(name)  \(text)")
            .lineSpacing(1.5)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(message.isMine ? GoofColors.accent.opacity(0.16) : Color.white.opacity(0.08))
            }
            .overlay {
                if message.isMine {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(GoofColors.accent.opacity(0.85), lineWidth: 1)
                }
            }
            .opacity(message.isReplay ? 0.5 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct MessageContextMenu: View {
    @Environment(AppModel.self) private var model
    let message: ChatMessage

    var body: some View {
        if !message.isMine {
            Menu("举报") {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.title) { model.report(message, reason: reason) }
                }
            }
            Button("屏蔽「\(message.displayName)」") { model.block(message) }
            Divider()
        }
        Button("复制") { model.copy(message) }
    }
}
