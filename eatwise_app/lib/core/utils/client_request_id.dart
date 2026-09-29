import 'dart:math';

/// UUIDv4 幂等键（客户端生成，D-20 / §2.2）。
///
/// 历史上定义在 streak_controller.dart（经其 export 保持既有引用可用）；
/// FastingPlanApi.putCurrent 等 fasting 链路也需要（PUT /fasting-plans/current
/// 的 PutPlanDto 强制 clientRequestId——缺失曾致全量方案上行 400，见
/// FastingPlanApi 注释），故下沉 core 共用。
String newClientRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
