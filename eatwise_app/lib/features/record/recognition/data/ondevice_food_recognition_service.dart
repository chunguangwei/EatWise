/// 端侧视觉拍照识别（Gemma4-E2B 多模态）：图片归一化 → 视觉推理 →
/// 宽松解析 → 食物库匹配 → 候选（Top-1 + 合成置信度）。
///
/// 定位与文本估算一致：识别名命中食物库后用**库内精准营养值**入账，
/// 模型估算值只作 sanity-clamp 存疑判定参考；任何一步失败都映射为
/// [RecognitionUnavailable]，与现有 UI 的 D-16 手动搜索兜底兼容。
///
/// 视觉链路实证（插件源码核对）：flutter_gemma 1.8.2 `Message.withImage`
/// 携带图片字节 → litertlm FFI 会话 `_pendingImages` → base64 入消息 JSON
/// → 原生 LiteRT-LM 视觉编码器；前提是 getActiveModel(supportImage: true)
/// （否则插件静默丢图，网关在 inferWithImage 显式拦截）。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';

/// 图片归一化抽象（解码缩放重编码；单测注入恒等实现避开 dart:ui 编解码）。
typedef PhotoImageNormalizer = Future<Uint8List> Function(Uint8List bytes);

/// 视觉输入长边上限（imagepilot visualTokenBudget 经验：≤768 足够分类，
/// 更大只涨 base64 体积与编码耗时，视觉编码器 token 数固定）。
const int kPhotoRecognitionMaxEdge = 768;

/// 生产图片归一化：长边 > [maxEdge] 时等比缩到 768 并重编码 PNG
/// （PNG 无损，插件自带 ImageProcessor 同样转 PNG 喂视觉编码器）；
/// 本就 ≤768 的原样返回（零重编码开销）。解码失败抛异常由上层映射降级。
Future<Uint8List> normalizeFoodPhoto(
  Uint8List bytes, {
  int maxEdge = kPhotoRecognitionMaxEdge,
}) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final probeFrame = await probe.getNextFrame();
  final width = probeFrame.image.width;
  final height = probeFrame.image.height;
  probeFrame.image.dispose();
  probe.dispose();
  final longEdge = width > height ? width : height;
  if (longEdge <= maxEdge) return bytes;
  final scale = maxEdge / longEdge;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: (width * scale).round(),
    targetHeight: (height * scale).round(),
  );
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('图片重编码失败（toByteData 返回 null）');
    }
    return data.buffer.asUint8List();
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

/// 端侧视觉拍照识别服务（模型已下载且开关启用时由
/// foodRecognitionServiceProvider 选用；否则保留远端 stub）。
final class OnDeviceFoodRecognitionService implements FoodRecognitionService {
  OnDeviceFoodRecognitionService({
    required this.gateway,
    required this.modelPath,
    required this.searchFoods,
    this.normalizeImage = normalizeFoodPhoto,
  });

  final OnDeviceLlmGateway gateway;

  /// 模型落盘路径（provider 已按快照判定 ready，此处**不触发下载**，
  /// 只取路径；与 FoodEstimateOrchestrator「未就绪不调 estimate」同约）。
  final Future<String> Function() modelPath;

  /// 食物库搜索（识别名映射回库内条目，D-16）。
  final Future<List<Food>> Function(String query) searchFoods;

  final PhotoImageNormalizer normalizeImage;

  /// OOM 后永久禁用（与端侧估算同策略：本设备不再重试，避免反复 OOM
  /// 杀进程；provider 重建实例前生效）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  @override
  Future<RecognitionOutcome> recognize(Uint8List imageBytes) async {
    if (_permanentlyDisabled) {
      return const RecognitionUnavailable('ondevice_disabled');
    }
    final Uint8List normalized;
    try {
      normalized = await normalizeImage(imageBytes);
    } on Object {
      return const RecognitionUnavailable('bad_image');
    }
    try {
      if (!gateway.isLoaded || !gateway.visionEnabled) {
        await gateway.load(await modelPath(), enableVision: true);
      }
      final raw = await gateway.inferWithImage(
        buildPhotoRecognitionPrompt(),
        normalized,
        systemInstruction: kPhotoRecognitionSystemPrompt,
        maxOutputTokens: 128, // 一行「名 => 4 数字」，比文本版多留名额度
      );
      final parsed = parsePhotoRecognitionOutput(raw);
      if (parsed == null) {
        // 含模型明说「无法识别」：透出原始回复，用户能看到模型实际看到
        // 了什么（detail 为空串时按 null 处理，走无详情 snackbar）。
        final detail = cleanRecognitionDetail(raw);
        return RecognitionUnavailable(
          'parse_failed',
          detail: detail.isEmpty ? null : detail,
        );
      }
      final match = await matchFoodByName(searchFoods, parsed.name);
      if (match == null) {
        // 识别名映射不回食物库：透出识别名（「识别为 xx 但库未收录」，
        // 引导换词手动搜索）；识别结果必须落回自建核心库，D-16，
        // 模型估值不直接入账。
        return RecognitionUnavailable(
          'no_match',
          detail: cleanRecognitionDetail(parsed.name),
        );
      }
      return RecognitionSuccess(<RecognizedCandidate>[
        RecognizedCandidate(
          food: match.food,
          defaultAmountG: 100,
          confidence: photoRecognitionConfidence(
            dubious: isNutritionEstimateDubious(parsed.values),
            exactNameMatch: match.exact,
          ),
        ),
      ]);
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return const RecognitionUnavailable('ondevice_oom');
    } on OnDeviceLlmException {
      return const RecognitionUnavailable('ondevice_error');
    } on Object {
      // 模型路径解析/搜索等意外错误：按不可用降级，不阻断记录主流程。
      return const RecognitionUnavailable('ondevice_error');
    }
  }
}
