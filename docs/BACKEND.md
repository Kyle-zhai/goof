# 接入服务器

Kuro 的仓库只包含客户端。所有和服务器打交道的地方都经过一个协议：[`ChatService`](../App/Kuro/Chat/ChatService.swift)。默认的 [`DemoChatService`](../App/Kuro/Chat/DemoChatService.swift) 在本机模拟房间；换成你自己的实现，Kuro 就成了真正的多人应用。

## 1. 实现协议

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

然后在 `ChatServiceFactory.make()` 里返回它。网络权限（`com.apple.security.network.client`）已经在 `project.yml` 的 entitlements 里打开了。`kind` 不是 `.demo` 之后，界面上的「演示」标记会自动消失。

## 2. 调用约定

| 方法 | 什么时候调用 | 要做什么 |
| --- | --- | --- |
| `updateProfile` | 启动时一次，之后资料每次变化 | 保存公开资料。`avatarPNG` 是 256×256 的 PNG，或者为 nil（用首字母头像） |
| `join(room:anonymous:)` | 进入房间。`room` 是 [`AppCatalog`](../Packages/KuroCore/Sources/KuroCore/AppCatalog.swift) 里的 id，比如 `figma` | 隐式离开上一个房间；加入这个房间的实时频道和在线列表；返回最近的回放消息，从旧到新 |
| `setAway` | 用户切到别的应用（还在 45 秒宽限期内），或者回来了 | 更新在线状态。离开中的人不计入在线人数 |
| `setAnonymous` | 用户切换匿名或实名 | 更新自己在在线列表里的显示 |
| `leave` | 宽限期结束、锁屏、睡眠、暂停 Kuro，或者用户关掉了这个应用的开关 | 离开频道和在线列表 |
| `send` | 用户发送弹幕 | 校验、保存、广播，返回别人看到的那条消息（带匿名昵称和 `authorKey`） |
| `report` | 右键举报 | 记录举报 |
| `block` / `blockedUsers` / `unblock` | 右键屏蔽，以及 Dashboard 的屏蔽列表 | 见下文 |

客户端保证：

- 所有调用都在主线程（MainActor）上。`onEvent` 也请在主线程上调用。
- `updateProfile`、`join`、`leave`、`setAway`、`setAnonymous` 会按顺序一个接一个调用，不会交错，所以「快速离开再进入」不会乱序。
- 发送前已经做过一遍长度、空白和频率检查（见 [`MessageRules`](../Packages/KuroCore/Sources/KuroCore/MessageRules.swift)），但客户端是可以被改的，服务器必须自己再检查一遍。

事件（`ChatEvent`）：

- `.message(ChatMessage)`：房间里的新消息。自己发的消息也可以再广播回来，客户端按 `id` 去重。
- `.hide(UUID)`：消息被审核移除，客户端会立刻把它从面板上拿掉。
- `.members([RoomMember])`：在线列表变化，每次给全量。

出错时抛出 [`ChatError`](../App/Kuro/Chat/ChatService.swift) 里对应的错误，界面会显示合适的提示：`rateLimited`、`duplicate`、`tooLong`、`notInRoom`、`needsNickname`、`banned`，其他情况用 `server(String)`。

## 3. 服务器必须保证的事

1. **只知道房间**。客户端只会把房间 id 发给服务器，不会发送任何其他应用的信息。不要提供「某个人在哪个房间」的查询；在线状态只在房间内部广播。
2. **匿名**。匿名消息的 `displayName` 由服务器生成，比如对「账号 + 房间 + 日期」做 HMAC，生成「匿名 · 动物·3 位十六进制」。同一天同一个房间里保持不变。永远不要把匿名者的账号 id 发给其他客户端，在线列表里也一样。
3. **authorKey**。每条消息带一个不透明的作者标识，客户端用它隐藏被屏蔽的人。它在同一房间、同一天内保持稳定，并且无法反推出账号（同样可以用 HMAC）。
4. **消息规则**。最长 80 个字；去掉控制字符、合并连续空白；每人每个房间 3 秒一条、每分钟最多 12 条；30 秒内的重复内容拒绝。
5. **回放**。`join` 返回最近 10 分钟内最多 50 条消息。消息只保存 24 小时左右：这是弹幕，不是聊天记录。
6. **举报**。记录举报理由；同一条消息被足够多的不同用户举报后自动隐藏，并广播 `.hide`。
7. **屏蔽**。按真实账号屏蔽，匿名的人也能被屏蔽。之后这个用户不会再收到被屏蔽者的消息，回放里也要过滤掉。`blockedUsers` 返回的 `label` 是屏蔽时看到的名字。
8. **封禁和新号限制**。被封禁的账号 `send` 时抛出 `ChatError.banned`；新注册的账号可以先限制几分钟不能发言，减少小号刷屏。
9. **资料**。昵称最多 24 个字，不能以「匿名」开头；用户名 2–20 位且全局唯一。

## 4. 可以怎么搭

- **Supabase**：Auth（Sign in with Apple）+ Realtime（每个房间一个私有频道：Broadcast 发消息，Presence 做在线列表）+ Postgres（资料、短期历史、举报、屏蔽；用 RLS 和 `security definer` 函数做校验和限流）+ `pg_cron` 定时清理过期消息。
- **Firebase**：Auth + Firestore 或 Realtime Database + Cloud Functions 做校验和限流。
- **自建**：WebSocket 服务 + Redis（在线列表和限流）+ 任意数据库。

## 5. 登录

协议里没有登录方法，因为不同后端的登录方式差别很大。可以在你的 `ChatService` 里处理，例如第一次 `join` 前先匿名登录，或者在 Dashboard 里加一个登录页。

使用 Sign in with Apple 需要付费的 Apple 开发者账号，还要在 `project.yml` 的 entitlements 里加上 `com.apple.developer.applesignin`，并把签名改成你自己的 team。
