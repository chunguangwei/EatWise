import 'package:eatwise/core/push/push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 推送服务（默认 [StubPushService]；接入 FCM/APNs/聚合 SDK 后在
/// main 中 override 为对应适配器，上层无感）。
final pushServiceProvider = Provider<PushService>((ref) {
  return StubPushService();
});
