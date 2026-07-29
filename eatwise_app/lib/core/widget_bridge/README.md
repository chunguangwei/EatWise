# core/widget_bridge — 锁屏/桌面小组件双端桥（《规格-M2 断食计时状态机》§8，D-17）

同步总原则（§8）：**传锚点不传剩余值**——只把「状态枚举 + 目标锚点 UTC 毫秒 + 归属日 + 方案/窗口标签」经 home_widget 写入共享容器（iOS App Group `group.com.eatwise.shared` / Android `HomeWidgetPreferences` SharedPreferences），倒计时由原生侧系统活控件自治渲染（iOS `Text(timerInterval:)` / Android `Chronometer`），App 内与小组件读同一锚点，误差 ≤1 分钟（§8.3）。

- `widget_data_provider.dart`：`WidgetDataProvider` 纯函数——周期快照 + `anchorsFor`（经 `resolveState`）→ `WidgetFastingData`（状态/锚点/归属日/方案标签）；文案经 `WidgetTextResolver` 注入（D-15 i18n）。
- `home_widget_gateway.dart`：home_widget 插件抽象（写共享键值、触发重渲染、点击深链流），测试可替身。
- `widget_sync_service.dart`：`WidgetSyncService`——共享键契约（`WidgetDataKeys`）、diff 跳过、失败降级不阻断计时；挂入通知 reschedule 同一触发链（见 `fasting_timer_controller.dart`）。
- `widget_deep_link.dart`：点击深链 `eatwise://widget/home` → 首页（冷/热启动两路）。

原生侧：Android `android/app/src/main/kotlin/com/eatwise/eatwise/EatWiseWidgetProvider.kt`（2×2/4×2，Chronometer 倒计时）；iOS `ios/EatWiseWidget/`（WidgetKit small/medium，App Group 与 Xcode target 配置步骤见其 README）。
