import KuroCore
import SwiftUI

struct PanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.panelCollapsed {
                CollapsedCapsule()
            } else {
                VStack(spacing: 0) {
                    PanelHeader()
                    Divider().opacity(0.4)
                    DanmakuView()
                    ComposerView()
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppIcon: View {
    let bundleID: String?
    var size: CGFloat = 16

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size)
        }
    }
}

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            AppIcon(bundleID: model.status.roomID)
            Text(model.currentApp?.name ?? "房间")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if model.isAway {
                Text("离开中").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(model.onlineCount)", systemImage: "person.2.fill")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .help("当前房间在线人数")
            Button {
                model.panelCollapsed = true
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("收起")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct CollapsedCapsule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.panelCollapsed = false
        } label: {
            HStack(spacing: 6) {
                AppIcon(bundleID: model.status.roomID, size: 14)
                Text(model.currentApp?.name ?? "Kuro").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "person.2.fill").font(.system(size: 10))
                Text("\(model.onlineCount)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .help("展开弹幕")
    }
}

private struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
            HStack(spacing: 6) {
                Button {
                    model.setPostAnonymously(!model.settings.postAnonymously)
                } label: {
                    Image(systemName: model.settings.postAnonymously ? "theatermasks.fill" : "person.crop.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.settings.postAnonymously ? Color.accentColor : .secondary)
                .help(model.settings.postAnonymously ? "匿名发送中（点击切换为实名）" : "实名发送中（点击切换为匿名）")

                TextField("发条弹幕…", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { model.send() }

                let remaining = MessageRules.maxLength - model.draft.count
                if remaining < 20 {
                    Text("\(remaining)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.black.opacity(0.06))
        .animation(.easeOut(duration: 0.2), value: model.notice)
    }
}
