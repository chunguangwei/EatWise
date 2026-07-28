# features/fasting/application — 断食用例编排层

- `fasting_notification_plan.dart`：未来 48h 通知计划纯逻辑（《规格-M2》§7.1/§7.2，D-09；三类提醒：进食前 15min、进食到点、断食开始到点；支持延长锚点后移 D-10、跨午夜窗口、夏令时）。
- `fasting_notification_scheduler.dart`：单一 `reschedule()` 重排入口（§7.2.3 全触发器）；先 cancelAll 再重建（§7.2.5）；权限拒绝返回降级标志不阻断计时（合规 §3）。
- `fasting_notification_texts.dart`：slang 文案适配器（复用 `notification.fasting.*` key）+ 渠道工厂。
- `fasting_system_events.dart`：时区/时间/重启事件源抽象与事件→重排绑定器（T14/T15/B14；平台桥接留 TODO）。
