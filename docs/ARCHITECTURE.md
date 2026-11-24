# Goof 设计说明

Goof 是一个 macOS 菜单栏应用：它知道你此刻在用哪个应用，把你放进「正在用同一个应用的人」的房间，在一个小小的悬浮面板里用弹幕聊天。

这个仓库只有客户端。所有和服务器有关的事情都经过 [`ChatService`](../App/Goof/Chat/ChatService.swift) 协议；没有接服务器时，`DemoChatService` 在本机模拟房间，界面会标「演示」。接入方法见 [BACKEND.md](BACKEND.md)。

## 1. 三个界面

| 界面 | 实现 |
| --- | --- |
| 菜单栏 | `MenuBarExtra`。显示当前房间和在线人数，可以切换弹幕样式、暂停、打开 Dashboard。应用不在 Dock 里出现（`LSUIElement`）。 |
| 悬浮面板 | 无边框的 `NSPanel`，带 `.nonactivatingPanel`，浮在所有窗口和全屏应用之上，跟随你切换桌面。可以拖动、缩放，收起成一个显示未读数的小胶囊。 |
| Dashboard | 普通窗口：应用、个人资料、弹幕外观、隐私与安全、通用五页，第一次启动时先显示三步引导。打开时应用临时出现在 Dock 和 ⌘Tab 里，关掉后回到你之前用的应用。 |

面板是「不激活」的：点进输入框打字时，前台应用仍然是你正在用的那个，所以打字不会把你踢出房间。这是整个检测方案能成立的前提。

## 2. 怎么判断「你在用什么」

目标：判断准确、不需要任何系统权限、不碰隐私、不来回抖动。

### 2.1 只读两个信号

1. **前台应用**：`NSWorkspace.didActivateApplicationNotification` 推送的 bundle id。
2. **距离上次输入的秒数**：`CGEventSource.secondsSinceLastEventType`，每秒读一次。它只是一个数字，不包含按了什么键。

另外，锁屏、睡眠、屏幕关闭、屏保、切换用户都会立刻算作离开。

Goof 自己和系统界面（Dock、Spotlight、通知中心、登录窗口等）出现在前台时不算切走，见 `AppCatalog.ignoredBundleIDs`。

### 2.2 状态机

[`RoomResolver`](../Packages/GoofCore/Sources/GoofCore/RoomResolver.swift) 是纯 Swift 的状态机，输入只有「事件 + 时间」，所以可以完整地单元测试。

```
            开启了的应用在前台，并且稳定 3 秒
  [不在房间] ─────────────────────────────────▶ [在房间 A]
      ▲                                           │
      │ 宽限期 45 秒到了                            │ 切走 / 2 分钟没操作
      │                                           ▼
      └──────────────────────────────────── [离开中 A]
                                                  │ 45 秒内回到 A
                                                  └────────▶ [在房间 A]

  锁屏、睡眠、暂停 Goof、关掉这个应用的开关：立刻离开
```

- **防抖 3 秒**：⌘Tab 快速扫过几个应用时，不会进出一串房间。
- **宽限期 45 秒**：切到别的应用查个东西再回来，你一直在房间里，面板不闪、回放不重载。这段时间你在在线列表里显示为「离开」，面板上有倒计时。
- **空闲阈值**：默认 2 分钟，可以在 Dashboard 里改成 1、5 或 10 分钟。人走开了，就不算在线。

### 2.3 为什么不做得更「聪明」

读窗口标题、当前文件或网页地址都需要辅助功能或屏幕录制权限，而且会碰到非常敏感的信息。Goof 的房间粒度就是「应用」，这些都用不上，所以也不申请。

## 3. 房间和白名单

- 房间只来自 [`AppCatalog`](../Packages/GoofCore/Sources/GoofCore/AppCatalog.swift) 里的应用，每个应用有一个稳定的 id（比如 `figma`），这个 id 就是房间 id。
- 同一个应用的不同版本共用一个房间：VS Code 和 VS Code Insiders、IntelliJ 旗舰版和社区版等，都写在同一个条目的 `bundleIDs` 里。
- 白名单只收「被人看到在用也无所谓」的工作类应用。浏览器、聊天、邮件、金融、健康类应用不收，测试里也会检查。规则见 [CONTRIBUTING.md](../CONTRIBUTING.md#adding-an-app)。
- 所有应用默认关闭，用户在引导或 Dashboard 里自己开启。

## 4. 弹幕

两种样式随时切换，正在等待显示的消息会带过去。

### 4.1 滚动弹幕

- [`DanmakuLayout`](../Packages/GoofCore/Sources/GoofCore/DanmakuLayout.swift) 分配轨道：所有弹幕速度相同，前一条的尾巴完全进入面板、再留出一点间距后，同一条轨道才放下一条，所以永远不会重叠。轨道都忙时消息排队，队列满了丢掉最旧的，像热闹的直播间一样。
- 每条弹幕先画成一张位图（`DanmakuBubble`），然后交给 Core Animation 从右移到左（`DanmakuScrollLayer`）。动画在系统的渲染进程里跑，Goof 不需要每帧醒来，空闲时不占 CPU。
- 鼠标停在弹幕上会冻结所有图层，方便阅读和右键；离开后从原位置继续，轨道的时间也一起顺延。

### 4.2 规整列表

一条条从下往上排，顶部渐隐。[`MessagePacer`](../Packages/GoofCore/Sources/GoofCore/MessagePacer.swift) 控制节奏：平时每 0.35 秒放一条，积压多了加快，避免一大批消息同时跳出来。

### 4.3 回放和节能

- 进入房间时，服务器返回的最近消息以半透明的「回放」样式先过一遍，之后只显示实时消息。
- 驱动弹幕的定时器只在有东西在动或在排队时运行，安静的房间里不会唤醒 CPU。

## 5. 焦点和键盘

- **⌃⌥⌘K**：用 Carbon 的 `RegisterEventHotKey` 注册全局快捷键，不需要辅助功能权限。按下后把光标放进面板的输入框。
- **Esc**：离开输入框并把焦点还给原来的应用。用中文输入法选字时按 Esc 只会取消选字，不会离开。
- 面板和 Dashboard 里的 ⌘X、⌘C、⌘V、⌘A、⌘Z 都能正常用（菜单栏应用没有「编辑」菜单，需要自己转发）。

## 6. 数据和隐私

| 数据 | 存在哪 | 会发给服务器吗 |
| --- | --- | --- |
| 开启了哪些应用、弹幕外观、空闲阈值、暂停到什么时候 | 本机 `UserDefaults` | 不会 |
| 当前前台的白名单应用（用来在菜单里提示「在 Figma 里开启弹幕」） | 只在内存里 | 不会 |
| 个人资料（昵称、用户名、简介、主题色） | 本机 `UserDefaults` | 会，作为公开资料 |
| 头像 | `~/Library/Application Support/Goof/avatar.png`，256×256 | 会，作为公开资料 |
| 当前房间 id、在线和离开状态 | 不保存 | 会，这是房间本身 |
| 发出的弹幕 | 不保存 | 会 |

- 不在白名单里的应用，Goof 不记录、也不上报，连「你在用一个不在白名单里的应用」都不会说。
- 别人看不到你在用哪些应用，只能看到同一个房间里的人。服务器需要遵守的规则见 [BACKEND.md](BACKEND.md#3-服务器必须保证的事)。
- 「屏幕共享和录屏时隐藏面板」使用 `NSWindow.sharingType = .none`。个别不遵守这个设置的录屏工具仍可能录到面板。
- Goof 不需要任何权限或 entitlements，默认也没有开启 App Sandbox：没有付费开发者签名时，每次编译出来的签名都不一样，沙盒应用每次更新都会被系统当成「另一个应用」，弹窗询问能不能访问它自己的数据。如果你用自己的 Developer ID 签名发布，可以在 `project.yml` 里加上 `com.apple.security.app-sandbox`、`com.apple.security.network.client`（连接服务器）和 `com.apple.security.files.user-selected.read-only`（选头像）。

## 7. 和服务器的接口

- [`AppModel`](../App/Goof/AppModel.swift) 是唯一调用 `ChatService` 的地方。
- 进入、离开、离开中、匿名切换、资料更新这几个调用排成一个队列，一个结束才开始下一个（`enqueue`）。快速离开再进入时，服务器看到的顺序不会乱。
- 服务器通过 `onEvent` 推送新消息、被隐藏的消息和在线列表。客户端按消息 id 去重，所以自己发的消息被广播回来也没关系。
- 发送前客户端先做长度、空白和频率检查（[`MessageRules`](../Packages/GoofCore/Sources/GoofCore/MessageRules.swift)），但服务器必须自己再检查一遍。

## 8. 代码结构

```
App/Goof/
  GoofApp.swift          菜单栏、应用入口、单实例
  AppModel.swift         全局状态：房间、在线、通知提示、所有设置的修改入口
  Activity/              前台应用、空闲和锁屏检测，喂给 RoomResolver
  Chat/                  ChatService 协议、消息模型、本地演示后端
  Panel/                 悬浮面板：滚动弹幕、规整列表、输入框、拖动和缩放
  Dashboard/             设置窗口和首次引导
  Settings/              本机设置和个人资料
  Support/               颜色、应用图标缓存、稳定哈希（匿名昵称）
  System/                全局快捷键、开机启动、编辑快捷键、截图渲染
Packages/GoofCore/       不依赖 AppKit 的逻辑和单元测试
  RoomResolver           在线判定状态机
  AppCatalog             白名单和 bundle id 归类
  DanmakuLayout          滚动弹幕的轨道分配
  MessagePacer           规整列表的节奏
  MessageRules           消息校验和客户端限流
  PauseDuration          「暂停 Goof」的时长
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，`.xcodeproj` 不进 git。不需要 Apple 开发者账号，默认用本机签名。

## 9. 测试和截图

- `swift test --package-path Packages/GoofCore` 跑核心逻辑的单元测试。
- `Goof --snapshot` 用演示数据把面板（两种样式和收起状态）、Dashboard 的每一页（浅色和深色）和引导渲染成 PNG，然后退出。它不碰真实设置，也不连接服务器。
- CI 在 macOS 上跑测试、编译、渲染截图，并把截图作为 artifacts 上传；改界面时可以下载对比。打 `v*` 标签时，另一个工作流会编译通用二进制并发布到 Releases。

## 10. 之后可以做的

- 英文界面（文字目前都写在代码里，需要先抽成 String Catalog）。
- Developer ID 签名、公证和自动更新（例如 Sparkle），这样下载的版本不会被系统拦。
- 一个可以直接部署的参考后端。
- VoiceOver 和键盘导航的完整支持。
