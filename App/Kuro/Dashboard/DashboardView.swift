import KuroCore
import SwiftUI

/// The dashboard window's content: onboarding on first run, then the dashboard.
struct DashboardRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.hasCompletedOnboarding {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .tint(KuroColors.accent)
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar()
                .frame(width: 216)
            // On an opaque base, so the line looks the same over any window background.
            Rectangle().fill(Palette.separator).frame(width: 1)
                .background(Palette.paneBackground)
            PaneContainer(pane: model.dashboardPane)
        }
        .ignoresSafeArea()
    }
}

private struct PaneContainer: View {
    let pane: DashboardPane

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(pane: pane)
                switch pane {
                case .apps: AppsPane()
                case .profile: ProfilePane()
                case .appearance: AppearancePane()
                case .privacy: PrivacyPane()
                case .general: GeneralPane()
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(Palette.paneBackground)
        .id(pane)
    }
}

private struct DashboardSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window buttons.
            Color.clear.frame(height: 42)

            HStack(spacing: 10) {
                KuroLogo(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Kuro").font(.system(size: 16, weight: .bold))
                        if model.isDemo { Tag(text: "演示") }
                    }
                    HStack(spacing: 5) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(model.statusSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(DashboardPane.allCases) { pane in
                    SidebarItem(pane: pane, selected: model.dashboardPane == pane) {
                        model.dashboardPane = pane
                    }
                }
            }

            Spacer(minLength: 12)

            MeCard()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if model.isSnapshot {
                Palette.sidebar
            } else {
                VisualEffectBackground(material: .sidebar)
            }
        }
    }

    private var statusColor: Color {
        if model.isPaused { return .secondary }
        if model.isAway { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        if model.isInRoom { return Palette.green }
        if model.pendingApp != nil { return Color(red: 0.35, green: 0.65, blue: 1) }
        return Color.secondary.opacity(0.6)
    }
}

private struct SidebarItem: View {
    let pane: DashboardPane
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: pane.tint) ?? .gray)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(pane.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Palette.sidebarSelection : Color.primary.opacity(hovering ? 0.05 : 0))
                    .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1.5, y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MeCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let profile = model.profile.profile
        Button {
            model.dashboardPane = .profile
        } label: {
            HStack(spacing: 10) {
                AvatarView(image: model.profile.avatar, name: profile.displayName.isEmpty ? "?" : profile.displayName,
                           accent: Color(hex: profile.accentHex) ?? KuroColors.accent, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName.isEmpty ? "还没有昵称" : profile.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(model.postsAnonymously ? "当前匿名发言" : (profile.username.isEmpty ? "实名发言" : "@\(profile.username)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("编辑个人资料")
    }
}
