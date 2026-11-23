import AppKit
import SwiftUI

/// Colors for the dashboard, tuned for both light and dark mode.
enum Palette {
    static let paneBackground = dynamic(light: "#F5F5F8", dark: "#1E1E22")
    static let card = dynamic(light: "#FFFFFF", dark: "#2A2A30")
    static let sidebar = dynamic(light: "#ECEDF2", dark: "#26262C")
    static let sidebarSelection = dynamic(light: "#FFFFFF", dark: "#3A3A42")
    static let chips = dynamic(light: "#E7E8EE", dark: "#34343B")
    static let chipSelection = dynamic(light: "#FFFFFF", dark: "#4A4A53")
    static let separator = Color.primary.opacity(0.08)
    static let green = Color(red: 0.12, green: 0.68, blue: 0.36)
    static let warning = Color(red: 0.86, green: 0.5, blue: 0.0)

    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light) ?? .windowBackgroundColor
        })
    }
}

enum GoofLinks {
    /// Change these in a fork.
    static let repository = URL(string: "https://github.com/Kyle-zhai/goof")!
    static let backendGuide = URL(string: "https://github.com/Kyle-zhai/goof/blob/main/docs/BACKEND.md")!
    static let addAnApp = URL(string: "https://github.com/Kyle-zhai/goof/blob/main/CONTRIBUTING.md#adding-an-app")!
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 2, y: 1)
    }
}

extension LinearGradient {
    /// The colored banner behind the current room and the profile header.
    static func accentBanner(_ tint: NSColor) -> LinearGradient {
        LinearGradient(colors: [Color(nsColor: tint.blended(withFraction: 0.08, of: .white) ?? tint),
                                Color(nsColor: tint.darker(0.32))],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            Card { content }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct RowDivider: View {
    var inset: CGFloat = 14

    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1).padding(.leading, inset)
    }
}

struct SwitchToggle: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering

    var body: some View {
        if isSnapshotRendering {
            SnapshotSwitch(isOn: isOn)
                .accessibilityLabel(label)
        } else {
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(label)
        }
    }
}

/// Screenshots only: the look of a small system switch in the window you are
/// using. Offscreen windows never become key, so the real switch would draw in
/// its inactive gray.
private struct SnapshotSwitch: View {
    let isOn: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let offTrack = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.1)
        Capsule()
            .fill(isOn ? GoofColors.accent : offTrack)
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 0.8, y: 0.5)
                    .padding(1.5)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct PaneHeader: View {
    let pane: DashboardPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pane.title)
                .font(.system(size: 22, weight: .bold))
            Text(pane.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }
}

struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.chips))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
    }
}

struct Tag: View {
    let text: String
    var color: Color = Color(red: 0.64, green: 0.37, blue: 0)
    var background: Color = Color(red: 1, green: 0.62, blue: 0.11).opacity(0.16)

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(background))
    }
}

struct ChipOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// A row of pill buttons, like a segmented control but lighter.
struct ChipPicker<Value: Hashable>: View {
    let options: [ChipOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minWidth: 34)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Palette.chipSelection : .clear)
                            .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 1, y: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.chips))
    }
}

/// A slider with its current value shown next to it.
struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .frame(width: 170)
                .accessibilityLabel(label)
            Text(format(value))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.2)))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A sample danmaku on a dark strip, used for previews in the dashboard.
struct DanmakuPreviewStrip: View {
    let messages: [ChatMessage]
    var style: DanmakuStyle = .scroll
    var fontSize: CGFloat = 13
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch style {
            case .scroll:
                HStack(spacing: 14) {
                    ForEach(messages) { message in
                        if let image = DanmakuBubble.nsImage(for: message, fontSize: fontSize, scale: displayScale) {
                            Image(nsImage: image)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            case .stack:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages) { message in
                        StackRow(message: message, fontSize: fontSize)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.22), Color(red: 0.1, green: 0.1, blue: 0.13)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .environment(\.colorScheme, .dark)
    }
}

extension ChatMessage {
    /// A message for previews in the dashboard and onboarding.
    static func sample(_ body: String, name: String, accentHex: String? = nil, anonymous: Bool = false,
                       mine: Bool = false) -> ChatMessage {
        ChatMessage(id: UUID(), room: "preview", body: body, isAnonymous: anonymous, displayName: name,
                    accentHex: anonymous ? nil : accentHex, avatarURL: nil, authorKey: name, createdAt: Date(),
                    isMine: mine)
    }
}
