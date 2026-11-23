# 参与贡献

谢谢你愿意让 Goof 变得更好。下面是动手前需要知道的事。

## 开发环境

- macOS 14 以上、Xcode 15.3 以上、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。
- 运行 `./scripts/bootstrap.sh` 生成 `Goof.xcodeproj`。工程以 `project.yml` 为准，`.xcodeproj` 不进 git；增删文件后重新运行一次 bootstrap 就行。
- 不需要 Apple 开发者账号，工程默认用本机签名（ad-hoc）。

## 测试

```sh
swift test --package-path Packages/GoofCore
```

- 能不依赖 AppKit 的逻辑都放进 `Packages/GoofCore`，并写单元测试。房间判定、白名单、弹幕轨道和消息规则都在那里。
- 改了界面的话，CI 会运行 `Goof --snapshot` 把面板、Dashboard 和新手引导渲染成截图，可以在这次 Actions 运行的 artifacts 里下载对比。本地也可以这样运行：

  ```sh
  xcodebuild -project Goof.xcodeproj -scheme Goof -derivedDataPath build build
  build/Build/Products/Debug/Goof.app/Contents/MacOS/Goof --snapshot
  ```

  截图目录会打印在最后一行。

<a id="adding-an-app"></a>

## 添加一个应用

Goof 只为「被人看到在用也无所谓」的工作类应用开房间。

| 可以加 | 不会加 |
| --- | --- |
| 开发工具、设计工具、办公和笔记、创作类软件、AI 助手 | 浏览器、聊天和社交、邮件、金融和支付、健康和医疗、约会、密码管理、VPN，以及任何「在用它」本身就会透露隐私的应用 |

步骤：

1. 查到应用的 bundle id：

   ```sh
   osascript -e 'id of app "Figma"'
   ```

2. 在 [`AppCatalog.swift`](Packages/GoofCore/Sources/GoofCore/AppCatalog.swift) 对应的分类里加一行：

   ```swift
   .init(id: "figma", name: "Figma", category: .design, bundleIDs: ["com.figma.Desktop"], tint: "#A259FF"),
   ```

   - `id` 是房间 id：小写字母、数字和短横线。它会存进用户设置、也会发给服务器，所以**发布后不能改名，也不能挪给别的应用用**。
   - 同一个应用的不同版本（正式版、预览版、社区版）放进同一个 `bundleIDs`，这样它们共用一个房间。
   - `tint` 是用户没安装这个应用时，图标方块的颜色。

3. 运行测试，它会检查 id 是否唯一、格式和颜色是否正确，以及白名单里没有浏览器或聊天类应用。
4. 提 PR，写清楚这是什么应用、为什么适合开房间。

## 隐私红线

下面这些改动不会被合并：

- 读取窗口标题或内容、按键内容、屏幕画面，或者申请辅助功能、屏幕录制等权限。
- 记录或上传白名单之外的应用信息。
- 让别人看到某个人在用哪些应用，或者让匿名消息能关联到账号。

## 代码约定

- Swift 5.10 语言模式。界面用 SwiftUI，确实需要时才用 AppKit（例如悬浮面板、滚动弹幕层、全局快捷键）。
- 用户能看到的文字目前都是中文，语气平实，像在跟朋友说话。
- 尽量不引入第三方依赖。
- 提交信息用英文，祈使句（例如 `Add Sketch to the catalog`）。
- 一个 PR 只做一件事；改了界面请附上前后截图。

## 接入服务器

想把 Goof 接到真实后端，请看 [docs/BACKEND.md](docs/BACKEND.md)。如果你做了一个可以复用的实现（比如 Supabase 版），欢迎在 issue 里分享。
