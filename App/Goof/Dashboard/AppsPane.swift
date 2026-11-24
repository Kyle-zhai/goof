import AppKit
import GoofCore
import SwiftUI

struct AppsPane: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: CatalogApp.Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NowCard()

            HStack(spacing: 10) {
                SearchField(text: $query)
                ChipPicker(options: categoryOptions, selection: $category)
                    .fixedSize()
            }

            let apps = filteredApps
            if apps.isEmpty {
                Text("No app found. Goof only has rooms for the apps on its list, and you can suggest new ones on GitHub.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                    ForEach(apps) { app in
                        AppCard(app: app)
                    }
                }
            }

            HStack {
                Text("\(model.settings.allowedApps.count) turned on · Apps start off, and only the ones you turn on put you in a room")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.settings.allowedApps.isEmpty {
                    Button("Turn All Off") { model.setApps(Array(model.settings.allowedApps), allowed: false) }
                        .controlSize(.small)
                }
            }

            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No rooms for browsers, messaging, email, finance or health apps")
                            .font(.system(size: 13, weight: .medium))
                        Text("What you do in them is too personal. Just being seen using one can give something away, so Goof keeps them off the list.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Missing an app? See how to add it", destination: GoofLinks.addAnApp)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.top, 2)
                    }
                }
                .padding(14)
            }
        }
    }

    private var categoryOptions: [ChipOption<CatalogApp.Category?>] {
        var options = [ChipOption<CatalogApp.Category?>(value: nil, title: "All")]
        for category in CatalogApp.Category.allCases {
            options.append(ChipOption(value: category, title: category.title))
        }
        return options
    }

    /// Installed apps first, then the rest, each group in catalog order.
    private var filteredApps: [CatalogApp] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return AppCatalog.apps.enumerated()
            .filter { _, app in
                (category == nil || app.category == category)
                    && (needle.isEmpty || app.name.lowercased().contains(needle) || app.id.contains(needle))
            }
            .sorted { lhs, rhs in
                let left = AppIconCache.isInstalled(lhs.element) ? 0 : 1
                let right = AppIconCache.isInstalled(rhs.element) ? 0 : 1
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map { $0.element }
    }
}

private struct NowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let app = model.currentApp {
            let tint = NSColor(hex: app.tint) ?? .systemBlue
            HStack(spacing: 14) {
                AppTile(app: app, size: 46)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("You're in the \(app.name) room")
                        .font(.system(size: 16, weight: .bold))
                    Text((model.isAway ? "Away · " : "") + "\(model.onlineCount) online. Only people in this room can see you")
                        .font(.system(size: 12))
                        .opacity(0.88)
                }
                Spacer()
                LiveBadge()
            }
            .padding(16)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient.accentBanner(tint))
            }
        } else {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: model.isPaused ? "moon.zzz.fill" : "bubble.left.and.bubble.right")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.chips))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isPaused ? "Goof is paused" : "You're not in a room")
                            .font(.system(size: 15, weight: .bold))
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.isPaused {
                        Button("Resume") { model.resume() }
                    } else if let app = model.frontmostDisabledApp {
                        Button("Turn On \(app.name)") { model.setApp(app.id, allowed: true) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }
        }
    }

    private var reason: String {
        if model.isPaused {
            return model.pauseUntilText.map { "Paused until \($0). You won't join any room before then" } ?? "You won't join any room until you resume"
        }
        if let app = model.pendingApp { return "You're using \(app.name). Joining its room…" }
        if let app = model.frontmostDisabledApp { return "You were just using \(app.name), but it isn't turned on" }
        if model.settings.allowedApps.isEmpty { return "Turn on the apps you use below. Switch to one and you'll join its room in 3 seconds" }
        return "Switch to an app you've turned on and you'll join its room in 3 seconds"
    }
}

private struct AppCard: View {
    @Environment(AppModel.self) private var model
    let app: CatalogApp

    var body: some View {
        let isOn = model.settings.allowedApps.contains(app.id)
        let installed = AppIconCache.isInstalled(app)
        let here = model.status.roomID == app.id
        HStack(spacing: 12) {
            AppTile(app: app, size: 38)
                .saturation(installed ? 1 : 0.35)
                .opacity(installed ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if here {
                    Text("● You're here · \(model.onlineCount) online")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.green)
                } else {
                    Text(app.category.title + (installed ? "" : " · Not installed"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            SwitchToggle(label: "Allow \(app.name)",
                         isOn: Binding(get: { isOn }, set: { model.setApp(app.id, allowed: $0) }))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? GoofColors.accent.opacity(0.55) : Palette.separator, lineWidth: isOn ? 1.5 : 1)
        }
        .shadow(color: isOn ? GoofColors.accent.opacity(0.1) : .black.opacity(0.03), radius: isOn ? 6 : 2, y: 1)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search apps"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 150)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
    }
}
