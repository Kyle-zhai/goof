# Kuro

和正在用同一个应用的人，一起发弹幕。

Kuro 是一个 macOS 菜单栏应用：它检测你当前在用的应用（只限你勾选过的），把你放进这个应用的房间，在一个可拖动、可折叠、总在最前的小面板里滚动弹幕。

- 设计文档：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 数据库：[supabase/migrations](supabase/migrations)

## 运行

需要 macOS 14+、Xcode 15.3+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
brew install xcodegen
./scripts/bootstrap.sh     # 生成 Kuro.xcodeproj（以及 Config.xcconfig）
open Kuro.xcodeproj
```

没有配置 Supabase 时，Kuro 以**离线演示模式**运行：房间里的人和弹幕都是模拟的，方便看界面和检测效果。

要连接真实后端，在 `Config.xcconfig` 里填入 Supabase 的 URL 和 anon key，并在 Supabase 里执行 `supabase/migrations` 下的 SQL（`supabase db push`）。

## 测试

```sh
swift test --package-path Packages/KuroCore
```

## 目录

```
App/Kuro/            macOS 应用（SwiftUI + AppKit）
Packages/KuroCore/   纯 Swift 逻辑：房间检测状态机、白名单、弹幕轨道、消息规则
supabase/            数据库结构、权限、限流、举报/屏蔽
docs/                设计文档
```
