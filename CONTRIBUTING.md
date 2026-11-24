# Contributing

Thanks for helping make Goof better. Here's what to know before you start.

## Setup

- macOS 14 or later, Xcode 15.3 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Run `./scripts/bootstrap.sh` to generate `Goof.xcodeproj`. `project.yml` is the source of truth and the `.xcodeproj` isn't checked in, so run bootstrap again after adding or removing files.
- No Apple Developer account needed: the project signs locally (ad-hoc) by default.

## Tests

```sh
swift test --package-path Packages/GoofCore
```

- Logic that doesn't need AppKit goes in `Packages/GoofCore`, with unit tests. Room resolution, the app list, danmaku lanes and message rules all live there.
- If you change the UI, CI runs `Goof --snapshot` to render the panel, the Dashboard and the welcome tour as screenshots. Download them from the run's artifacts to compare. You can also run it locally:

  ```sh
  xcodebuild -project Goof.xcodeproj -scheme Goof -derivedDataPath build build
  build/Build/Products/Debug/Goof.app/Contents/MacOS/Goof --snapshot
  ```

  The last line of output is the screenshot folder.

<a id="adding-an-app"></a>

## Adding an app

Goof only has rooms for work apps that nobody minds being seen using.

| Welcome | Won't be added |
| --- | --- |
| Developer tools, design tools, productivity and notes, creative apps, AI assistants | Browsers, messaging and social, email, finance and payments, health, dating, password managers, VPNs, and any app where being seen using it gives something private away |

Steps:

1. Find the app's bundle id:

   ```sh
   osascript -e 'id of app "Figma"'
   ```

2. Add a line under the right category in [`AppCatalog.swift`](Packages/GoofCore/Sources/GoofCore/AppCatalog.swift):

   ```swift
   .init(id: "figma", name: "Figma", category: .design, bundleIDs: ["com.figma.Desktop"], tint: "#A259FF"),
   ```

   - `id` is the room id: lowercase letters, digits and hyphens. It's saved in people's settings and sent to the server, so **once released it can't be renamed or given to another app**.
   - Put every edition of an app (release, beta, community) in the same `bundleIDs`, so they share one room.
   - `tint` colors the icon tile when the app isn't installed.

3. Run the tests. They check that ids are unique, that ids and colors are well formed, and that no browser or messaging app is on the list.
4. Open a PR that says what the app is and why it suits a room.

## Privacy lines

These changes won't be merged:

- Reading window titles or contents, keystrokes or the screen, or asking for Accessibility, Screen Recording or similar permissions.
- Recording or sending anything about apps that aren't on the list.
- Letting people see which apps someone uses, or tying anonymous messages to an account.

## Code style

- Swift 5.10 language mode. SwiftUI for the UI, and AppKit only where it's really needed (the floating panel, the scrolling danmaku layer, the global shortcut).
- UI text is in English: plain, short and friendly, like talking to a friend.
- Avoid third-party dependencies.
- Commit messages in the imperative (for example `Add Sketch to the catalog`).
- One change per PR. If you change the UI, include before and after screenshots.

## Connecting a server

To connect Goof to a real backend, see [docs/BACKEND.md](docs/BACKEND.md). If you build an implementation others can reuse (say, a Supabase one), share it in an issue.
