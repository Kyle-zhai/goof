import AppKit
import SwiftUI

struct AppearancePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Style")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 12) {
                    ForEach(DanmakuStyle.allCases) { style in
                        StyleCard(style: style, selected: settings.danmakuStyle == style) {
                            model.setStyle(style)
                        }
                    }
                }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, settings.danmakuStyle == .scroll, !model.isSnapshot {
                    Label("Reduce Motion is on, so Stacked is recommended", systemImage: "figure.walk.motion")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            SettingsSection(title: "Details") {
                SettingsRow(title: "Scrolling speed",
                            subtitle: settings.danmakuStyle == .scroll ? "How far messages move each second" : "Only applies to the Scrolling style") {
                    ValueSlider(label: "Scrolling speed",
                                value: Binding(get: { settings.danmakuSpeed }, set: { model.setSpeed($0) }),
                                range: 50...160, step: 5) { "\(Int($0))" }
                        .disabled(settings.danmakuStyle != .scroll)
                }
                RowDivider()
                SettingsRow(title: "Text size") {
                    ChipPicker(options: DanmakuFontSize.allCases.map { ChipOption(value: $0, title: $0.title) },
                               selection: Binding(get: { settings.fontSize }, set: { model.setFontSize($0) }))
                }
                RowDivider()
                SettingsRow(title: "Panel background", subtitle: "Lower is more see-through, higher is easier to read") {
                    ValueSlider(label: "Panel background",
                                value: Binding(get: { settings.panelOpacity }, set: { settings.panelOpacity = $0 }),
                                range: 0.35...0.9, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
                }
                RowDivider()
                SettingsRow(title: "Replay recent messages when you join", subtitle: "Shown fainter, so you can catch up on the conversation") {
                    SwitchToggle(label: "Replay recent messages",
                                 isOn: Binding(get: { settings.replayHistory }, set: { settings.replayHistory = $0 }))
                }
                RowDivider()
                SettingsRow(title: "Show the panel", subtitle: "When off, only the menu bar icon stays. You still join and leave rooms") {
                    SwitchToggle(label: "Show the panel",
                                 isOn: Binding(get: { settings.panelEnabled }, set: { model.setPanelEnabled($0) }))
                }
            }

            SettingsSection(title: "Panel",
                            footer: "Hover over a message to stop it, so you can read it or right-click to report it. Drag the title bar or the messages to move the panel, and the bottom-right corner to resize it.") {
                SettingsRow(title: "Can't find the panel?", subtitle: "Moves it back to the bottom-right corner at its default size") {
                    Button("Reset Position") { model.resetPanelPosition() }
                }
            }
        }
    }
}

private struct StyleCard: View {
    let style: DanmakuStyle
    let selected: Bool
    let action: () -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.24), Color(red: 0.1, green: 0.1, blue: 0.14)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipped()
                    .environment(\.colorScheme, .dark)
                HStack(spacing: 10) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? GoofColors.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.title).font(.system(size: 13, weight: .semibold))
                        Text(style.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? GoofColors.accent : Color.secondary.opacity(0.5))
                }
                .padding(12)
            }
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? GoofColors.accent : Palette.separator, lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected ? GoofColors.accent.opacity(0.15) : .black.opacity(0.03), radius: selected ? 8 : 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch style {
        case .scroll:
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.scrollSamples.enumerated()), id: \.offset) { _, sample in
                        if let image = DanmakuBubble.nsImage(for: sample.message, fontSize: 12, scale: displayScale) {
                            Image(nsImage: image)
                                .offset(x: width * sample.x, y: sample.y)
                        }
                    }
                }
            }
            // The same soft edges as the real panel.
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                       .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
        case .stack:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.stackSamples) { message in
                    StackRow(message: message, fontSize: 12)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 8)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.4)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private static let scrollSamples: [(message: ChatMessage, x: CGFloat, y: CGFloat)] = [
        (.sample("Afternoon, all!", name: "Yuzu", accentHex: "#FF7A85"), 0.04, 12),
        (.sample("+1", name: "Kiki", accentHex: "#FF6FB5"), 0.68, 12),
        (.sample("Same here", name: "Anon Otter·a3f", anonymous: true), 0.28, 36),
        (.sample("It works!!", name: "Leo", accentHex: "#FF9F1C"), 0.06, 60),
        (.sample("Coffee #3", name: "Momo", accentHex: "#FFB347"), 0.5, 60),
        (.sample("Loving this feature", name: "Kai", accentHex: "#5AC8FA"), 0.2, 84),
    ]

    private static let stackSamples: [ChatMessage] = [
        .sample("Coffee #3", name: "Momo", accentHex: "#FFB347"),
        .sample("Afternoon, all!", name: "Yuzu", accentHex: "#FF7A85"),
        .sample("It works!!", name: "Leo", accentHex: "#FF9F1C"),
        .sample("Loving this feature", name: "Kai", accentHex: "#5AC8FA"),
    ]
}
