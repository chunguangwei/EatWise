# core/notification — 本地通知封装（D-09，《规格-M2 断食计时状态机》§7）

- `notification_types.dart`：权限状态 / 渠道定义 / 定时通知值对象（UTC epoch 秒，D-07）。
- `notification_service.dart`：抽象接口（初始化、权限申请/查询、即时/定时通知、cancelAll），便于测试替身。
- `local_notification_service.dart`：flutter_local_notifications 生产实现——iOS UNUserNotificationCenter（alert/badge/sound）、Android NotificationChannel + 精确闹钟（SCHEDULE_EXACT_ALARM 未授权自动降级不精确闹钟，合规 §3.2）。

上层调度逻辑见 `lib/features/fasting/application/`（48h 窗口全量重排，先 cancelAll 再重建，§7.2）。
