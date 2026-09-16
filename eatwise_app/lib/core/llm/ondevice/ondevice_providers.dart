/// 端侧小模型 AI 估算的 riverpod 接线骨架。
///
/// 设置页 / 自定义食物 UI 由后续棒次接入；本文件只提供：
/// - [onDeviceModelManagerProvider]：下载管理器单例（进度条/换源/取消/删除）；
/// - [onDeviceModelSnapshotProvider]：状态流（启动时先 refresh 校正磁盘实况）；
/// - [onDeviceLlmGatewayProvider]：推理网关单例（引擎单租户，全局共享）；
/// - [onDeviceNutritionEstimatorProvider]：估算编排（食物库未命中兜底入口）。
///
/// 测试覆盖方式：override 上述 provider 注入 Fake（网关/HTTP/能力探测均可换）。
library;

import 'package:eatwise/core/llm/ondevice/flutter_gemma_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_nutrition_estimator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载管理器（默认 Dio 直连 CDN + 放行能力探测；设备内存/磁盘探测
/// 插件就绪后在此 override 注入真实 [DeviceCapabilityProbe]）。
final onDeviceModelManagerProvider = Provider<OnDeviceModelManager>((ref) {
  final manager = OnDeviceModelManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// 模型状态流（下载进度/暂停/就绪/失败）；首帧前先按磁盘实况 refresh。
final onDeviceModelSnapshotProvider = StreamProvider<OnDeviceModelSnapshot>((
  ref,
) async* {
  final manager = ref.watch(onDeviceModelManagerProvider);
  await manager.refresh();
  yield manager.snapshot;
  yield* manager.snapshots;
});

/// 推理网关（flutter_gemma 实现；测试 override 为 Fake，切勿在单测实例化）。
final onDeviceLlmGatewayProvider = Provider<OnDeviceLlmGateway>((ref) {
  return FlutterGemmaGateway();
});

/// 端侧营养估算编排（食物库未命中兜底；OOM 永久禁用逻辑在编排内部）。
final onDeviceNutritionEstimatorProvider = Provider<OnDeviceNutritionEstimator>(
  (ref) {
    return OnDeviceNutritionEstimator(
      modelManager: ref.watch(onDeviceModelManagerProvider),
      gateway: ref.watch(onDeviceLlmGatewayProvider),
    );
  },
);

/// 后台预热端侧引擎（只 load 不推理）：设置页打开「优先使用端侧估算」
/// 开关后调用，把 text-only → enableVision 的重建成本从首拍路径挪到
/// 后台，首拍即热。模型未就绪时直接返回；任何失败静默（拍照/估算路径
/// 会按原逻辑重试并有自己的降级）。
Future<void> prewarmOnDeviceEngine({
  required Future<String> Function() modelPath,
  required bool Function() isModelReady,
  required OnDeviceLlmGateway gateway,
}) async {
  if (!isModelReady()) return;
  try {
    if (!gateway.isLoaded || !gateway.visionEnabled) {
      await gateway.load(await modelPath(), enableVision: true);
    }
  } on Object {
    // 静默：使用路径会重试加载并走各自降级（OOM 永久禁用等）。
  }
}
