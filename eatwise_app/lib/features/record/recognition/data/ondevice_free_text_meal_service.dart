/// 一句话自由记（端侧文本推理）：语音转写/手输文本 → 明细协议文本版
/// 推理 → 复用视觉版七段解析器 → 逐条库匹配 → 明细候选列表。
/// 任何失败返回 null（UI 回落既有词典解析路径，不破坏）。
library;

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/domain/free_text_meal_logic.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';

/// 端侧自由记服务（模型已下载且开关启用时由 freeTextMealServiceProvider
/// 提供；否则为 null，UI 回落词典解析）。
final class OnDeviceFreeTextMealService {
  OnDeviceFreeTextMealService({
    required this.gateway,
    required this.modelPath,
    required this.searchFoods,
  });

  final OnDeviceLlmGateway gateway;

  /// 模型落盘路径（provider 已按快照判定，此处不触发下载）。
  final Future<String> Function() modelPath;

  /// 食物库搜索（明细名映射回库内条目，D-16）。
  final Future<List<Food>> Function(String query) searchFoods;

  /// OOM 后永久禁用（与拍照识别/端侧估算同策略）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  /// 解析一句饮食描述 → 明细候选；解析空/引擎异常/模型未就绪返回 null。
  Future<List<RecognizedMealItem>?> parse(String text) async {
    if (_permanentlyDisabled) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      if (!gateway.isLoaded || !gateway.visionEnabled) {
        // 统一以视觉能力加载：与拍照识别/OCR 共用一个热引擎，避免
        // 文本-only 与视觉配置来回重建（重建一次数秒）。
        await gateway.load(await modelPath(), enableVision: true);
      }
      final raw = await gateway.infer(
        buildFreeTextMealPrompt(trimmed),
        systemInstruction: kFreeTextMealSystemPrompt,
        maxOutputTokens: 384, // 多行明细，与拍照识别同额度
      );
      final parsedItems = parsePhotoRecognitionItems(raw); // 七段同构复用
      if (parsedItems.isEmpty) return null;
      return <RecognizedMealItem>[
        for (final parsed in parsedItems)
          await recognizedMealItemFromParsed(searchFoods, parsed),
      ];
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return null;
    } on Object {
      return null; // 引擎/路径异常：静默回落词典解析
    }
  }
}
