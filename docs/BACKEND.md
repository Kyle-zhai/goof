# Connecting a server

This repository is the client only. Everything that talks to a server goes through one protocol, [`ChatService`](../App/Goof/Chat/ChatService.swift). The default [`DemoChatService`](../App/Goof/Chat/DemoChatService.swift) simulates rooms on the Mac; swap in your own implementation and Goof becomes a real multiplayer app.

## 1. Implement the protocol

```swift
@MainActor
final class MyChatService: ChatService {
    var onEvent: ((ChatEvent) -> Void)?
    let kind: BackendKind = .server(name: "chat.example.com")

    func updateProfile(_ profile: PublicProfile) async throws { /* … */ }
    func join(room: String, anonymous: Bool) async throws -> [ChatMessage] { /* … */ }
    func setAway(_ away: Bool) async { /* … */ }
    func setAnonymous(_ anonymous: Bool) async { /* … */ }
    func leave() async { /* … */ }
    func send(_ body: String, anonymous: Bool) async throws -> ChatMessage { /* … */ }
    func report(_ message: ChatMessage, reason: ReportReason) async throws { /* … */ }
    func block(authorOf message: ChatMessage) async throws { /* … */ }
    func blockedUsers() async throws -> [BlockedUser] { /* … */ }
    func unblock(_ user: BlockedUser) async throws { /* … */ }
}
```

Then return it from `ChatServiceFactory.make()`. Once `kind` isn't `.demo`, the Demo tags in the UI go away on their own. Goof doesn't turn on the App Sandbox, so it can use the network as is; if you sandbox it, add `com.apple.security.network.client` to the entitlements in `project.yml`.

## 2. How the client calls it

| Method | When | What to do |
| --- | --- | --- |
| `updateProfile` | Once at launch, then whenever the profile changes | Store the public profile. `avatarPNG` is a 256×256 PNG, or nil (initials avatar) |
| `join(room:anonymous:)` | Entering a room. `room` is an id from [`AppCatalog`](../Packages/GoofCore/Sources/GoofCore/AppCatalog.swift), such as `figma` | Implicitly leave the previous room; join this room's live channel and presence; return recent messages to replay, oldest first |
| `setAway` | The user switched to another app (still within the 45-second grace period), or came back | Update presence. People who are away don't count as online |
| `setAnonymous` | The user switched between anonymous and named | Update how they appear in presence |
| `leave` | The grace period ended, the screen locked, the Mac slept, Goof was paused, or the user turned this app off | Leave the channel and presence |
| `send` | The user sent a message | Validate, store and broadcast it, and return the message as others see it (with the anonymous name and `authorKey`) |
| `report` | Right-click › Report | Record the report |
| `block` / `blockedUsers` / `unblock` | Right-click › Block, and the blocked list in the Dashboard | See below |

The client guarantees:

- Every call happens on the main actor. Please call `onEvent` on the main actor too.
- `updateProfile`, `join`, `leave`, `setAway` and `setAnonymous` are called one after another and never overlap, so leaving and quickly rejoining can't arrive out of order.
- Messages are checked for length, whitespace and rate before sending (see [`MessageRules`](../Packages/GoofCore/Sources/GoofCore/MessageRules.swift)), but clients can be modified, so the server must check again.
- When `join` throws (no network, a server restart, Wi-Fi not back yet after wake), the client keeps retrying at 2, 4, 8, 16 and 30 seconds for as long as the user stays in that app, and shows the problem only once. Every `ChatError` except `server` is treated as "retrying won't help" and isn't retried.
- `blockedUsers` is called at launch and whenever the Dashboard opens.

Your implementation is responsible for:

- **The connection.** When the live connection drops, reconnect, rejoin the current room and report presence again on your own; the client doesn't know about disconnects. If you can't connect during `join`, throw and the client will retry.
- **`isMine`.** Broadcast messages don't carry `isMine`. Set `isMine = true` on the user's own messages in what `send` returns, in their broadcasts coming back, and in the `join` replay. The simplest way is for the server to tell the client "your `authorKey` in this room today" on `join`, and compare each message. The client has a fallback too: after `send` returns, it remembers that `authorKey` and treats later messages with the same key as the user's own; and if the broadcast arrives before `send` returns, it restyles the message it already showed.
- **Decoding JSON.** The models' `CodingKeys` are snake_case (`display_name`, `author_key`, `created_at`, …). Decode with `ChatWire.decoder()`: it parses ISO 8601 dates with a time zone, including Postgres-style microseconds, which the default `JSONDecoder` can't.

Events (`ChatEvent`):

- `.message(ChatMessage)`: a new message in the room. You may broadcast the user's own messages back; the client removes duplicates by `id`.
- `.hide(UUID)`: a message was removed by moderation; the client takes it off the panel right away.
- `.members([RoomMember])`: presence changed. Always send the full list.

On errors, throw the matching [`ChatError`](../App/Goof/Chat/ChatService.swift) so the UI shows the right message: `rateLimited`, `duplicate`, `tooLong`, `notInRoom`, `needsNickname` or `banned`, and `server(String)` for anything else.

## 3. What the server must guarantee

1. **It only knows about rooms.** The client only ever sends a room id, never anything about other apps. Don't offer any way to look up which room someone is in; presence is only broadcast inside a room.
2. **Anonymity.** The server generates the `displayName` of anonymous messages, for example from an HMAC of account + room + date, in the form “Anon Animal·3 hex digits”. It stays the same within one room for one day. Never send an anonymous person's account id to other clients, presence included.
3. **authorKey.** Every message carries an opaque author key, which clients use to hide people they blocked. It's stable within one room for one day and can't be traced back to the account (an HMAC works here too).
4. **Message rules.** Up to 80 characters; strip control characters and collapse runs of whitespace; per person per room, one message every 3 seconds and at most 12 a minute; reject repeats within 30 seconds.
5. **Replay.** `join` returns up to 50 messages from the last 10 minutes. Keep messages for about 24 hours only: this is danmaku, not a chat log.
6. **Reports.** Record the reason. Once enough different people report a message, hide it automatically and broadcast `.hide`.
7. **Blocking.** Block by the real account, so anonymous people can be blocked too. From then on the user doesn't receive the blocked person's messages, including in replays. The `label` that `blockedUsers` returns is the name the user saw when they blocked.
8. **Bans and new accounts.** `send` from a banned account throws `ChatError.banned`. You can also keep brand-new accounts from posting for a few minutes, to slow down throwaway accounts.
9. **Profiles.** Names are up to 24 characters and can't start with “Anon”; usernames are 2–20 characters and globally unique.

## 4. Ways to build it

- **Supabase:** Auth (Sign in with Apple) + Realtime (a private channel per room: Broadcast for messages, Presence for the online list) + Postgres (profiles, short history, reports and blocks, with RLS and `security definer` functions for validation and rate limits) + `pg_cron` to clean up expired messages.
- **Firebase:** Auth + Firestore or Realtime Database + Cloud Functions for validation and rate limits.
- **Your own:** a WebSocket service + Redis (presence and rate limits) + any database.

## 5. Keys and configuration

The client is open source, and anyone can take a shipped app apart, so **only public values belong in the client**: the server address and keys designed to be public (such as Supabase's anon key, which relies on RLS). Admin keys, Supabase's `service_role` key, database passwords and HMAC salts belong on the server only.

If your fork is public, it's best not to commit even the public values: put them in `Config.xcconfig` (already in `.gitignore`), include it through `configFiles` in `project.yml`, and read them with `$(VARIABLE_NAME)` in Info.plist.

## 6. Avatars

`updateProfile` hands you a 256×256 avatar PNG, and `ChatMessage.avatarURL` is ready for it, but the panel currently shows only the user's own avatar: messages show a name and name color, and presence is only used for the count. So uploading avatars is optional; `avatarURL` will be used once messages can show avatars.

## 7. Signing in

The protocol has no sign-in method, because backends sign people in very differently. Handle it inside your `ChatService`, for example by signing in anonymously before the first `join`, or add a sign-in page to the Dashboard.

Sign in with Apple needs a paid Apple Developer account: add the entitlement (`com.apple.developer.applesignin`) to Goof in `project.yml` and switch signing to your own team.
