/// 营养表拍照 OCR（端侧视觉，复用拍照识别的引擎管线）：读包装营养成分表
/// 每 100g 四营养 → 预填自定义食物/条码补录表单。任何失败返回 null
///（UI 降级手动填写/纯佐证，不阻断表单）。
library;

import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart';

/// 营养表读数结果（每 100g 值 + 存疑标记）。
final class LabelOcrReading {
  const LabelOcrReading({required this.values, required this.dubious});

  /// 读出的每 100g 营养（kJ 已在解析层换算 kcal）。
  final OnDeviceNutritionValues values;

  /// 合理性校验命中（宏量超限/折算偏差/热量物理上限）→ UI 标「请核对」。
  final bool dubious;
}

/// 端侧营养表 OCR 服务（模型已下载且开关启用时由
/// nutritionLabelOcrServiceProvider 提供；否则为 null，UI 降级）。
final class OnDeviceNutritionLabelOcrService {
  OnDeviceNutritionLabelOcrService({
    required this.gateway,
    required this.modelPath,
    this.normalizeImage = normalizeFoodPhoto,
  });

  final OnDeviceLlmGateway gateway;

  /// 模型落盘路径（provider 已按快照判定，此处不触发下载）。
  final Future<String> Function() modelPath;

  /// 图片归一化（默认生产实现；单测注入恒等避开 dart:ui 编解码）。
  final PhotoImageNormalizer normalizeImage;

  /// OOM 后永久禁用（与拍照识别/端侧估算同策略）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  /// 读一张营养表照片；读不出/引擎异常/模型未就绪返回 null。
  Future<LabelOcrReading?> read(Uint8List imageBytes) async {
    if (_permanentlyDisabled) return null;
    final Uint8List normalized;
    try {
      normalized = await normalizeImage(imageBytes);
    } on Object {
      return null; // 图片解码失败
    }
    try {
      if (!gateway.isLoaded || !gateway.visionEnabled) {
        await gateway.load(await modelPath(), enableVision: true);
      }
      final raw = await gateway.inferWithImage(
        buildNutritionLabelPrompt(),
        normalized,
        systemInstruction: kNutritionLabelOcrSystemPrompt,
        maxOutputTokens: 96, // 单行「能量 单位 => 三宏量」，比识别更短
      );
      final values = parseNutritionLabelOutput(raw);
      if (values == null) return null;
      return LabelOcrReading(
        values: values,
        dubious: isNutritionLabelReadingDubious(values),
      );
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return null;
    } on Object {
      return null; // 引擎/路径异常：静默降级
    }
  }
}
