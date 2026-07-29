# ios/EatWiseWidget — 断食计时 WidgetKit 小组件（代码备好，Xcode target 需人工添加）

实现口径：《规格-M2 断食计时状态机》§8.1 + 设计规范 §4.5。Dart 侧
`WidgetSyncService`（`lib/core/widget_bridge/`）经 home_widget 把
「状态枚举 + 目标锚点 UTC 毫秒 + 本地化文案」写入 App Group
`group.com.eatwise.shared`（**传锚点不传剩余值**），本扩展读同一容器，
倒计时由 SwiftUI `Text(_:style: .timer)` 系统级自治渲染，与 App 内误差 ≤1 分钟。

## 人工步骤（Xcode，约 10 分钟）

1. **New Target**：Xcode 打开 `ios/Runner.xcworkspace` → File → New → Target
   → **Widget Extension** → Product Name 填 `EatWiseWidget`，语言 Swift，
   **取消勾选** "Include Live Activity"（Live Activity 为 iOS 16.1+ 增强项，
   D-14 后续单独加 target）与 "Include Configuration App Intent"。
   - Deployment Target 设 **iOS 15.0**（D-14 最低版本）。
   - 创建后**删除模板生成的 `EatWiseWidget.swift` 等占位文件**。
2. **加入本目录文件**：把 `ios/EatWiseWidget/EatWiseWidget.swift` 拖入
   `EatWiseWidget` group（target membership 勾选 EatWiseWidget）；
   `EatWiseWidget.entitlements` 设为该 target 的 Code Signing Entitlements
   （Build Settings → Code Signing Entitlements → `EatWiseWidget/EatWiseWidget.entitlements`）。
3. **App Groups（两端都要）**：
   - `EatWiseWidget` target → Signing & Capabilities → + App Groups →
     添加 `group.com.eatwise.shared`（与 `kWidgetAppGroupId` 一致）。
   - `Runner` target 同样添加 `group.com.eatwise.shared`
     （home_widget 的 `setAppGroupId` 才能把数据写进共享容器）。
   - 〔待外部确认〕group 前缀随正式 Apple Developer 账号的 App ID
     能力配置最终确认（技术选型 §3 标注 bundle 前缀为假设值）。
4. **深链**：小组件 `widgetURL(eatwise://widget/home)` 经 home_widget
   `widgetClicked` 送达 Dart → 跳首页；无需额外 URL Scheme 注册
   （home_widget 插件在 AppDelegate 层拦截该 URI）。
5. **验证**：真机/模拟器跑 Runner → 桌面添加「断食计时」小组件 →
   App 内启动方案/延长/结束断食，小组件应随触发链刷新；倒计时与 App 内
   读数差 ≤1 分钟（§8.3 验收口径）。

## 说明

- 文案：Dart 侧按当前语言写好（D-15），本扩展只做展示，不做本地化逻辑。
- 刷新：Dart 触发链调 `HomeWidget.updateWidget(iOSName: 'EatWiseWidget')`
  → `reloadAllTimelines()`；timeline 另在锚点到点处预约一次系统刷新兜底。
- Live Activity（iOS 16.1+）：增强项（D-14 非阻断），本目录未实现；
  后续新增 target 时复用同一 App Group 锚点数据。
