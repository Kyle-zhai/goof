# How Goof works

Goof is a macOS menu bar app. It knows which app you're using right now, puts you in a room with everyone else using the same app, and lets you chat in danmaku on a small floating panel.

This repository is the client only. Everything that involves a server goes through the [`ChatService`](../App/Goof/Chat/ChatService.swift) protocol. Without a server, `DemoChatService` simulates rooms on the Mac and the UI shows a Demo tag. See [BACKEND.md](BACKEND.md) for connecting one.

## 1. Three surfaces

| Surface | Implementation |
| --- | --- |
| Menu bar | `MenuBarExtra`. Shows the current room and online count, and lets you switch the message style, pause Goof and open the Dashboard. The app doesn't appear in the Dock (`LSUIElement`). |
| Floating panel | A borderless `NSPanel` with `.nonactivatingPanel`. It floats above every window and full-screen app and follows you across Spaces. You can drag and resize it, or collapse it into a small capsule with an unread count. |
| Dashboard | A regular window with five panes: Apps, Profile, Appearance, Privacy and General. The first launch shows a three-step welcome tour first. While it's open, Goof shows up in the Dock and ⌘Tab; closing it returns you to the app you were using. |

The panel never activates: when you click into the input field and type, the app you're using stays frontmost, so typing doesn't kick you out of the room. The whole detection scheme depends on this.

## 2. Knowing what you're using

Goals: accurate, no system permissions, no private data, no flapping.

### 2.1 Only two signals

1. **The frontmost app**: the bundle id from `NSWorkspace.didActivateApplicationNotification`.
2. **Seconds since the last input**: `CGEventSource.secondsSinceLastEventType`, read once a second. It's only a number and says nothing about which keys were pressed.

On top of that, locking the screen, sleeping, the display turning off, the screen saver and fast user switching all count as leaving right away.

Goof itself and system UI (the Dock, Spotlight, Notification Center, the login window and so on) don't count as switching away when they come to the front; see `AppCatalog.ignoredBundleIDs`.

### 2.2 State machine

[`RoomResolver`](../Packages/GoofCore/Sources/GoofCore/RoomResolver.swift) is a pure Swift state machine whose only inputs are events and time, so it can be fully unit tested.

```
             an app you turned on is in front for 3 seconds
  [no room] ─────────────────────────────────────────────▶ [in room A]
      ▲                                                        │
      │ 45-second grace period ends                            │ switch away / 2 minutes idle
      │                                                        ▼
      └──────────────────────────────────────────────── [away from A]
                                                               │ back to A within 45 seconds
                                                               └──────────▶ [in room A]

  Locking the screen, sleeping, pausing Goof or turning the app off: leave right away
```

- **3-second debounce**: flicking through apps with ⌘Tab doesn't drag you through a string of rooms.
- **45-second grace period**: pop out to look something up and come back, and you never left. The panel doesn't flicker and the replay doesn't reload. Meanwhile you show as away in presence, and the panel shows a countdown.
- **Idle threshold**: 2 minutes by default, and 1, 5 or 10 minutes in the Dashboard. If you've stepped away, you don't count as online.

### 2.3 Why not be "smarter"

Reading window titles, the open file or the current URL needs Accessibility or Screen Recording permission, and touches very sensitive information. Goof's rooms are per app, so it needs none of that and doesn't ask.

## 3. Rooms and the app list

- Rooms only come from apps in [`AppCatalog`](../Packages/GoofCore/Sources/GoofCore/AppCatalog.swift). Each app has a stable id (such as `figma`), and that id is the room id.
- Editions of one app share a room: VS Code and VS Code Insiders, IntelliJ Ultimate and Community and so on are listed in the same entry's `bundleIDs`.
- The list only takes work apps that nobody minds being seen using. Browsers, messaging, email, finance and health apps are left out, and the tests check this. See the rules in [CONTRIBUTING.md](../CONTRIBUTING.md#adding-an-app).
- Every app starts off; people turn them on themselves in the welcome tour or the Dashboard.

## 4. Danmaku

You can switch between the two styles at any time, and messages waiting to be shown carry over.

### 4.1 Scrolling

- [`DanmakuLayout`](../Packages/GoofCore/Sources/GoofCore/DanmakuLayout.swift) assigns lanes. Every message moves at the same speed, and a lane only takes the next message once the previous one's tail is fully inside the panel plus a small gap, so messages never overlap. When every lane is busy, messages queue up, and a full queue drops the oldest, just like a busy livestream.
- Each message is first drawn as a bitmap (`DanmakuBubble`), then Core Animation moves it from right to left (`DanmakuScrollLayer`). The animation runs in the system's render server, so Goof doesn't wake up every frame and uses no CPU while idle.
- Hovering over a message freezes every layer, so you can read it or right-click it. When the pointer leaves, everything continues from where it stopped and the lane timings shift with it.

### 4.2 Stacked

Messages line up from the bottom and fade out at the top. [`MessagePacer`](../Packages/GoofCore/Sources/GoofCore/MessagePacer.swift) sets the rhythm: one message every 0.35 seconds normally, faster when a backlog builds up, so a burst of messages doesn't pop in all at once.

### 4.3 Replay and power use

- When you join a room, the recent messages from the server play through first in a translucent replay style; after that only live messages appear.
- The timer that drives the danmaku only runs while something is moving or queued, so a quiet room doesn't wake the CPU.

## 5. Focus and keyboard

- **⌃⌥⌘K**: a global shortcut registered with Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. It puts the cursor in the panel's input field.
- **Esc**: leaves the input field and gives focus back to the app you were using. While you're picking characters in an input method (Chinese, Japanese and so on), Esc only cancels the candidates.
- ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z work in the panel and the Dashboard (a menu bar app has no Edit menu, so Goof forwards them itself).

## 6. Data and privacy

| Data | Where it's stored | Sent to the server? |
| --- | --- | --- |
| Which apps are on, appearance, idle threshold, pause end time | `UserDefaults` on the Mac | No |
| The frontmost app when it's on the list but turned off (for the menu's “Turn On Goof for Figma”) | Memory only | No |
| Profile (name, username, bio, accent color) | `UserDefaults` on the Mac | Yes, as the public profile |
| Avatar | `~/Library/Application Support/Goof/avatar.png`, 256×256 | Yes, as the public profile |
| Current room id, online and away status | Not stored | Yes, that's the room itself |
| Messages you send | Not stored | Yes |

- Goof doesn't record or report apps that aren't on the list. It doesn't even say "you're using an app that isn't on the list".
- Nobody can see which apps you use; they only see the people in the same room. See the rules a server must follow in [BACKEND.md](BACKEND.md#3-what-the-server-must-guarantee).
- "Hide the panel when sharing or recording the screen" uses `NSWindow.sharingType = .none`. The odd recording tool that ignores this setting may still capture the panel.
- Goof needs no permissions or entitlements, and doesn't turn on the App Sandbox by default: without a paid developer signature, every build gets a different signature, so macOS treats each update of a sandboxed app as "another app" and asks whether it may access its own data. If you ship with your own Developer ID, you can add `com.apple.security.app-sandbox`, `com.apple.security.network.client` (to reach the server) and `com.apple.security.files.user-selected.read-only` (to pick an avatar) in `project.yml`.

## 7. The server interface

- [`AppModel`](../App/Goof/AppModel.swift) is the only place that calls `ChatService`.
- Joining, leaving, going away, switching anonymity and profile updates go through one queue, and each starts only after the previous one finishes (`enqueue`). When you leave and quickly rejoin, the server never sees them out of order.
- The server pushes new messages, hidden messages and presence through `onEvent`. The client removes duplicates by message id, so it's fine for the user's own messages to be broadcast back.
- The client checks length, whitespace and rate before sending ([`MessageRules`](../Packages/GoofCore/Sources/GoofCore/MessageRules.swift)), but the server must check again.

## 8. Code layout

```
App/Goof/
  GoofApp.swift          Menu bar, app entry point, single instance
  AppModel.swift         App state: room, presence, notices, and every settings change
  Activity/              Frontmost app, idle and lock detection, fed into RoomResolver
  Chat/                  ChatService protocol, message models, local demo backend
  Panel/                 Floating panel: scrolling danmaku, stacked list, input, drag and resize
  Dashboard/             Settings window and welcome tour
  Settings/              Local settings and profile
  Support/               Colors, app icon cache, stable hash (anonymous names)
  System/                Global shortcut, launch at login, edit shortcuts, snapshot rendering
Packages/GoofCore/       Logic without AppKit, with unit tests
  RoomResolver           Presence state machine
  AppCatalog             App list and bundle id matching
  DanmakuLayout          Lane assignment for scrolling danmaku
  MessagePacer           Rhythm of the stacked list
  MessageRules           Message validation and client-side rate limits
  PauseDuration          How long "Pause Goof" lasts
```

The project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), and the `.xcodeproj` isn't checked in. No Apple Developer account is needed: it signs locally by default.

## 9. Tests and screenshots

- `swift test --package-path Packages/GoofCore` runs the unit tests for the core logic.
- `Goof --snapshot` renders the panel (both styles and collapsed), every Dashboard pane (light and dark) and the welcome tour to PNGs with demo data, then quits. It doesn't touch real settings or connect to a server.
- CI runs the tests, builds the app and renders the screenshots on macOS, then uploads them as artifacts, so UI changes can be compared. Pushing a `v*` tag runs another workflow that builds a universal binary and publishes it to Releases.

## 10. What's next

- Other languages: UI text is written in code for now, so it needs to move into a String Catalog first.
- Developer ID signing, notarization and automatic updates (for example with Sparkle), so downloads aren't blocked by macOS.
- A reference backend you can deploy as is.
- Full VoiceOver and keyboard navigation support.
