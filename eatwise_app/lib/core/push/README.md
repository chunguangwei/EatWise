# core/push — 推送抽象层（《技术选型与双端架构》§3「推送」行，D-17）

定位：营销/社区互动推送的统一客户端抽象。**M2 窗口提醒走本地通知**
（`core/notification`，D-09），不依赖本层在线。

- `push_service.dart`：`PushService` 接口（initialize / register / unregister /
  token / token 刷新流 / 前台消息流 / 点击路由流）+ `StubPushService`
  （默认实现，全链路打日志不抛异常）；FCM/APNs/厂商聚合 SDK（个推/极光）
  适配器 TODO 与凭据配置位（google-services.json、APNs .p8、三环境隔离）
  见文件尾部注释——〔待外部确认〕Firebase 项目与 Apple Developer 账号。
- `push_providers.dart`：`pushServiceProvider`（默认 Stub，接入真实通道后
  在 main override，上层无感）。
