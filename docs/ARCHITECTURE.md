# Kuro 架构与计划

Kuro 是一个 macOS 菜单栏应用：它知道你此刻在用哪个应用，把你放进「正在用同一个应用的所有人」的房间，在一个小小的悬浮面板里用弹幕的方式实时聊天。

本文是第一版设计，目的是在深入开发前先对齐方向。

---

## 1. 产品形态

| 部分 | 说明 |
| --- | --- |
| 菜单栏图标 | 常驻，显示当前房间和在线人数；可以开关面板、打开 Dashboard、暂停 Kuro。不在 Dock 显示（`LSUIElement`）。 |
| 悬浮面板 | 小尺寸、可拖动、可折叠成一个小胶囊、总在最前。弹幕只在面板内部从右向左滚动；底部是输入框；顶部显示房间名和在线人数。 |
| Dashboard 窗口 | 三个页面：**应用**（勾选允许加入房间的应用）、**个人资料**（用户名、头像、简介、头像框颜色，像直播账号）、**隐私与安全**（默认匿名/实名、屏蔽列表、空闲判定时长、暂停）。 |

面板使用 `NSPanel` + `.nonactivatingPanel`：点进输入框打字时，**你正在用的应用依然是前台应用**，所以不会因为打字把自己踢出房间。这是检测方案能成立的关键细节。

---

## 2. 「你在用什么」的检测方案

目标：判断准确、零额外权限、尊重隐私、不抖动。

### 2.1 信号

1. **前台应用**：`NSWorkspace.didActivateApplicationNotification`，拿到 `bundleIdentifier`（例如 `com.anthropic.claudefordesktop`）。这是事件推送，不需要轮询，也**不需要任何系统权限**（不需要辅助功能、不需要屏幕录制）。
2. **是否真的在用**：`CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)` 读取「距离上次键盘/鼠标输入的秒数」，每 5 秒读一次。同样不需要权限（它只给一个时间数，不读按键内容）。
3. **离开电脑**：锁屏（`com.apple.screenIsLocked` 分布式通知）、休眠（`NSWorkspace.willSleepNotification`）、屏保启动、切换用户（`sessionDidResignActive`）都立刻视为离开。

### 2.2 状态机（`KuroCore/RoomResolver`）

```
             前台是白名单应用 且 已稳定 3s
   [无房间] ──────────────────────────────▶ [在房间 A]
      ▲                                       │
      │  宽限期 45s 到期                       │ 切走 / 空闲 > 2min / 锁屏
      │                                       ▼
      └──────────────────────────────── [离开中 A（宽限）]
                                              │ 宽限期内切回 A
                                              └──────────▶ [在房间 A]
```

- **防抖 3 秒**：Cmd-Tab 快速扫过几个应用时不会进出一串房间。
- **宽限期 45 秒**：短暂切到浏览器查个东西再回来，你一直在房间里、面板不闪、历史不重载。宽限期内在线列表里你显示为「离开」。
- **空闲 2 分钟**（可在 Dashboard 调）：前台虽然是 Figma，但人已经走开了，就不计入在线人数。
- **Kuro 自己**、系统 UI（Dock、登录窗口、Spotlight 等）永远不算「切走」，不会触发离开。
- 状态机是纯 Swift、不依赖 AppKit，输入是「事件 + 时间」，便于单元测试（见 `KuroCoreTests`）。

### 2.3 为什么不用更「聪明」的方案

- 读窗口标题 / 当前文件 / 网页 URL：需要辅助功能或屏幕录制权限，而且会泄露非常敏感的信息。Kuro 的房间粒度就是「应用」，不需要。
- 浏览器里的网站（比如网页版 Figma）：第一版不做。之后如果要做，可以做一个可选的浏览器扩展，只上报白名单域名。

---

## 3. 隐私模型

- **只有你勾选的应用**才会让你进入房间。默认白名单是一批不敏感的工作应用（Claude、Figma、VS Code、Cursor、Xcode、Notion、Linear、Slack…），且全部默认**关闭**，首次启动在引导里让用户自己勾。
- 不在白名单内的应用：**不上报任何东西**，连「你在用一个不在白名单里的应用」都不上报（客户端直接视为无房间）。
- **别人永远看不到你在用什么应用**。服务器端没有「某人在哪个房间」的公开查询；在线状态只在房间频道内广播，你只能看到你自己所在房间的在线人数和成员。个人资料页不包含任何应用信息。
- 同一个房间里的人天然知道「这些人也在用这个应用」，这是产品本身。所以实名模式下，同房间的人能看到你的昵称；匿名模式下，在线列表里也只显示匿名昵称，presence 的 key 是每次启动随机生成的，不带账号 id。
- **匿名发言**：别人只能看到「匿名 · 某某动物」这类当天、当房间有效的随机昵称，无法关联到你的账号；服务器保留真实 user_id 仅用于举报和封禁。
- 房间是按应用 bundle id 划分的公共频道，频道名是 `room:<bundle id>`。

---

## 4. 后端：Supabase

选它的理由：一个服务同时解决 **登录（含 Sign in with Apple）**、**实时通道（Broadcast + Presence）**、**Postgres（资料、短历史、举报、屏蔽）**、**行级安全（RLS）**，有官方 Swift SDK，前期免运维。

### 4.1 组成

| 能力 | 用法 |
| --- | --- |
| Auth | Sign in with Apple（主）+ 邮箱 Magic Link（备）。 |
| Realtime Presence | 每个房间一个私有频道 `room:<bundle id>`，客户端 `track` 自己的状态（显示名、头像、是否匿名、是否离开）。在线人数 = presence 数。 |
| Realtime Broadcast | 新消息通过数据库触发器 `realtime.broadcast_changes` 广播到房间频道，客户端不能直接往频道里发消息（只能写表），这样限流和过滤在服务器端统一生效。 |
| Postgres | `profiles`、`messages`、`blocks`、`reports`、`bans`。 |
| pg_cron | 每 10 分钟删除 24 小时前的消息。 |

### 4.2 消息与历史（参考直播弹幕）

- 消息是**纯实时**的：在线的人通过 Broadcast 立刻收到。
- 进入房间时，拉取最近 **50 条、且不早于 10 分钟**的消息作为「回放」，用较淡的样式快速滚过，告诉你刚才大家在聊什么。之后只显示实时消息。
- 服务器只保存 24 小时，过期自动删除。没有无限翻页的聊天记录，这不是 IM。
- 单条最长 80 字（弹幕要短）。

### 4.3 安全、审核与限流（真产品必须有）

- **限流**（数据库触发器，绕不过去）：每人每房间 3 秒 1 条、每分钟最多 12 条；重复发送相同内容会被拒绝。
- **内容过滤**：客户端和服务器各做一次长度/空白/控制字符校验；服务器端预留敏感词表 `banned_terms`。之后可接入第三方审核 API（Edge Function）。
- **举报**：任意消息可举报，写入 `reports`；同一条消息被 3 个不同用户举报后自动隐藏。
- **屏蔽**：屏蔽某人后，历史和实时消息都不再显示他（匿名消息也能屏蔽：按消息屏蔽，服务器解析到真实用户）。
- **封禁**：`bans` 表，被封禁用户无法写消息，可设到期时间。
- **新号限制**：账号创建 10 分钟内不能发言（降低小号刷屏）。
- 用户名唯一、3–20 字符，有保留词表。

---

## 5. 客户端结构

```
App/Kuro/                    # macOS 应用（SwiftUI + 少量 AppKit）
  KuroApp.swift              # MenuBarExtra + Dashboard 窗口
  AppModel.swift             # 全局状态：当前房间、消息、在线、设置
  Activity/                  # NSWorkspace / CGEventSource 适配层 → 喂给 RoomResolver
  Panel/                     # NSPanel 悬浮面板 + 弹幕视图 + 输入框
  Dashboard/                 # 应用勾选、个人资料、隐私
  Services/                  # ChatService 协议，Supabase 实现 + 本地 Mock 实现
Packages/KuroCore/           # 纯 Swift 逻辑，可单测
  RoomResolver               # 检测状态机
  AppCatalog                 # 白名单
  DanmakuLayout              # 弹幕轨道分配（不重叠）
  MessageRules               # 消息校验、客户端限流
supabase/migrations/         # 数据库结构、RLS、触发器、定时任务
```

- 没配置 Supabase 时，自动使用 **Mock 服务**（本地假用户 + 假消息），可以直接运行看 UI 和检测效果。
- 工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成（`project.yml`），避免 `.xcodeproj` 合并冲突。

---

## 6. 路线图

| 阶段 | 内容 |
| --- | --- |
| **M0 骨架**（本 PR） | 架构文档、工程骨架、检测状态机 + 单测、悬浮面板 + 弹幕、Dashboard 三个页面、Mock 服务、数据库迁移初稿。 |
| M1 联网 | Supabase 项目、Sign in with Apple、真实 Presence/Broadcast、历史回放、头像上传（Storage）。 |
| M2 安全 | 举报/屏蔽/封禁 UI、服务器端敏感词、新号限制、管理后台（先用 Supabase Studio）。 |
| M3 打磨 | 引导流程、开机自启（`SMAppService`）、面板主题和透明度、弹幕密度/速度设置、快捷键唤起输入框、本地化（中/英）。 |
| M4 发布 | Developer ID 签名 + 公证、Sparkle 自动更新、官网、隐私政策。 |

---

## 7. 需要你决定 / 提供的

1. **Apple Developer 账号**：Sign in with Apple 和公证发布都需要（$99/年）。
2. **Supabase 项目**：可以你建好后给我 URL 和 anon key（anon key 可以公开放在客户端）。
3. 默认白名单是否要调整（见 `Packages/KuroCore/Sources/KuroCore/AppCatalog.swift`）。
