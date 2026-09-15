/// 端侧营养估算编排：模型管理器 + 推理网关 + 纯函数层的粘合（application 风格）。
///
/// 定位（spike §7-10）：本地食物库未命中时的**兜底估算**，结果带
/// [OnDeviceNutritionEstimate.dubious] 存疑标记，UI 必须走「用户可编辑确认」
/// 流转，不能当精确值直接入库。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';

/// 一次端侧估算的结果。
final class OnDeviceNutritionEstimate {
  const OnDeviceNutritionEstimate({
    required this.values,
    required this.dubious,
  });

  final OnDeviceNutritionValues values;

  /// sanity-clamp 命中（宏量超限或热量折算偏差 >50%）→ UI 标记「估算存疑」。
  final bool dubious;
}

final class OnDeviceNutritionEstimator {
  OnDeviceNutritionEstimator({
    required this.modelManager,
    required this.gateway,
  });

  final OnDeviceModelManager modelManager;
  final OnDeviceLlmGateway gateway;

  /// OOM 后永久禁用（本设备不再尝试端侧加载，避免反复 OOM 杀进程；
  /// 上层捕获 [OnDeviceLlmMemoryException] 后应回退服务端/云端估算链路）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  /// 估算每 100g 营养。模型未下载会触发下载（UI 应先经管理器确认就绪再调）。
  /// 解析失败返回 null（建议上层重试一次再降级）；引擎异常抛
  /// [OnDeviceLlmException] 子类；下载异常抛 [OnDeviceModelException] 子类。
  Future<OnDeviceNutritionEstimate?> estimate(String foodName) async {
    if (_permanentlyDisabled) {
      throw const OnDeviceLlmMemoryException('端侧估算已因内存不足被永久禁用');
    }
    final path = await modelManager.ensureModel();
    if (!gateway.isLoaded) {
      try {
        await gateway.load(path);
      } on OnDeviceLlmMemoryException {
        _permanentlyDisabled = true;
        rethrow;
      }
    }
    String raw;
    try {
      raw = await gateway.infer(
        buildNutritionPrompt(foodName),
        systemInstruction: kOnDeviceNutritionSystemPrompt,
      );
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      rethrow;
    }
    final values = parseNutritionOutput(raw);
    if (values == null) return null;
    return OnDeviceNutritionEstimate(
      values: values,
      dubious: isNutritionEstimateDubious(values),
    );
  }
}
