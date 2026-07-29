/// 推送抽象层（《技术选型与双端架构》§3 桥接表「推送」行，D-17）。
///
/// 定位：**营销/社区互动推送**的统一客户端抽象——token 注册与上报、
/// 前台消息流、点击路由（go_router 深链）。M2 窗口提醒走本地通知
/// （`core/notification`，D-09），**不依赖本层在线**。
///
/// 通道规划（技术选型 §3）：
/// - iOS：APNs（token 经服务端注册）；
/// - Android 海外：FCM（随英文版海外上架启用，D-15）；
/// - Android 国内：厂商通道（华为/小米/OPPO/vivo/荣耀）经聚合推送 SDK，
///   选型个推或极光 M0 定〔待外部确认：商务与合规评估〕；
///   落地时在各自适配器内初始化厂商 SDK 并把厂商 token 一并上报，
///   对上层仍收敛为单一 [PushService] 接口。
///
/// 凭据配置位（〔待外部确认〕Firebase 项目与 Apple Developer 账号）：
/// - FCM：`android/app/google-services.json` + `ios/Runner/GoogleService-Info.plist`
///   （三环境隔离，技术选型 §6：禁止入库入仓，--dart-define=ENV 注入）；
/// - APNs：服务端持 APNs Auth Key（.p8），客户端只需 entitlements
///   `aps-environment`（dev/prod 三环境隔离）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 推送消息（客户端可见的最小载荷）。
final class PushMessage {
  const PushMessage({required this.title, required this.body, this.data});

  final String title;
  final String body;

  /// 自定义载荷（深链路由、业务 id 等，服务端契约统一定义）。
  final Map<String, Object?>? data;
}

/// 推送点击（携带路由信息，由应用层映射 go_router 深链）。
final class PushTap {
  const PushTap({required this.message, this.route});

  final PushMessage message;

  /// 目标路由（如 `/community`、`/data/reports`）；空 → 首页。
  final String? route;
}

/// 推送服务统一抽象。
///
/// 上层（应用层/路由层）只依赖本接口；FCM/APNs/厂商聚合 SDK 各写适配器
/// 实现本接口即可互换。
abstract interface class PushService {
  /// 初始化并请求推送权限（iOS 触发系统弹窗；Android 13+ 复用
  /// POST_NOTIFICATIONS）。权限拒绝降级：不阻断 App（合规 §3）。
  Future<void> initialize();

  /// 向服务端注册当前设备 token（登录态变化后也应重注册）。
  /// 实现层负责幂等（token 未变不重复上行）。
  Future<void> register();

  /// 注销（退出登录时；服务端解绑 user ↔ token）。
  Future<void> unregister();

  /// 当前 token（未注册/不可用为 null）。
  Future<String?> getToken();

  /// token 刷新流（FCM onTokenRefresh / APNs didRegister 更新）。
  Stream<String> get onTokenRefresh;

  /// 前台收到的消息流（由应用层决定展示横幅/静默处理）。
  Stream<PushMessage> get onForegroundMessage;

  /// 消息点击流（冷/热启动统一），应用层据此路由跳转。
  Stream<PushTap> get onMessageTap;
}

/// 默认 Stub 实现：不接任何真实通道，全链路打日志。
///
/// 用途：M0–M2 占位（窗口提醒本来就走本地通知），以及测试/开发环境
/// 无推送凭据时的安全兜底。所有方法均不抛异常。
final class StubPushService implements PushService {
  StubPushService({void Function(String message)? logger})
    : _logger = logger ?? debugPrint;

  final void Function(String message) _logger;

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  final StreamController<PushMessage> _messageController =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushTap> _tapController =
      StreamController<PushTap>.broadcast();

  bool _initialized = false;
  String? _token;

  @override
  Future<void> initialize() async {
    _initialized = true;
    _logger('StubPushService.initialize（无真实推送通道，降级打日志）');
  }

  @override
  Future<void> register() async {
    _token = 'stub-token';
    _logger('StubPushService.register → token=$_token（未上行）');
  }

  @override
  Future<void> unregister() async {
    _logger('StubPushService.unregister（token=$_token）');
    _token = null;
  }

  @override
  Future<String?> getToken() async => _token;

  @override
  Stream<String> get onTokenRefresh => _tokenController.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => _messageController.stream;

  @override
  Stream<PushTap> get onMessageTap => _tapController.stream;

  /// 测试/调试用：手动注入一条 token 刷新事件。
  void emitTokenRefresh(String token) => _tokenController.add(token);

  /// 测试/调试用：手动注入一条前台消息。
  void emitForegroundMessage(PushMessage message) =>
      _messageController.add(message);

  /// 测试/调试用：手动注入一次消息点击。
  void emitMessageTap(PushTap tap) => _tapController.add(tap);

  /// 是否已初始化（测试断言用）。
  bool get initialized => _initialized;

  /// 释放流资源。
  Future<void> dispose() async {
    await _tokenController.close();
    await _messageController.close();
    await _tapController.close();
  }
}

// TODO(push-FCM)：FcmPushService 适配器——firebase_messaging 插件；
//   凭据 google-services.json / GoogleService-Info.plist
//   〔待外部确认〕Firebase 项目（三环境隔离，--dart-define=ENV 注入）；
//   随英文版海外上架启用（D-15），国内 Android 不依赖 GMS。
// TODO(push-APNs)：ApnsPushService 适配器——iOS 侧经 firebase_messaging
//   或原生 UNUserNotificationCenter + didRegisterForRemoteNotifications；
//   entitlements 加 aps-environment；服务端持 APNs Auth Key(.p8)
//   〔待外部确认〕Apple Developer 账号。
// TODO(push-OEM)：国内厂商通道（华为/小米/OPPO/vivo/荣耀）经聚合推送 SDK
//   （个推/极光，M0 定〔待外部确认〕商务与合规评估，D-17/D-18 SDK 清单公示）；
//   适配器内初始化聚合 SDK、聚合 token 与 FCM token 一并上报服务端路由。
