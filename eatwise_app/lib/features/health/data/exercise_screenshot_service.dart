/// 运动截图识别服务（端侧视觉，Gemma4-E2B 多模态）：图片归一化 →
/// 视觉推理（严格 JSON 协议）→ 宽松解析 → [ExerciseScreenshotData]。
///
/// 链路复用拍照识别的模型配置/调用方式（`OnDeviceLlmGateway.load
/// (enableVision: true)` + `inferWithImage`）；任何一步失败映射为
/// [ExerciseScreenshotUnavailable]，引擎缺失/未就绪由 UI 前置引导卡
/// （ai_engine_guide_card）覆盖，不落「无法识别」死胡同。
library;

import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/health/domain/exercise_screenshot_logic.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart'
    show cleanRecognitionDetail;

/// 截图识别结果（成功 / 不可用两态，与 RecognitionOutcome 同构）。
sealed class ExerciseScreenshotOutcome {
  const ExerciseScreenshotOutcome();
}

final class ExerciseScreenshotSuccess extends ExerciseScreenshotOutcome {
  const ExerciseScreenshotSuccess(this.data);

  final ExerciseScreenshotData data;
}

final class ExerciseScreenshotUnavailable extends ExerciseScreenshotOutcome {
  const ExerciseScreenshotUnavailable(this.reason, {this.detail});

  /// 原因码（timeout / bad_image / parse_failed / ondevice_*）。
  final String reason;

  /// 可透出的模型原文（parse_failed 时非空，用户能看到模型实际看到了什么）。
  final String? detail;
}

/// 运动截图识别服务抽象（测试注入 fake；生产为端侧实现）。
abstract interface class ExerciseScreenshotService {
  /// 识别一张截图；[imageBytes] 为 JPEG/PNG 字节。
  Future<ExerciseScreenshotOutcome> recognize(Uint8List imageBytes);
}

/// 端侧视觉运动截图识别服务（模型已下载且开关启用时由
/// exerciseScreenshotServiceProvider 选用；否则为 null → UI 引导卡兜底）。
final class OnDeviceExerciseScreenshotService
    implements ExerciseScreenshotService {
  OnDeviceExerciseScreenshotService({
    required this.gateway,
    required this.modelPath,
    this.normalizeImage = normalizeFoodPhoto,
  });

  final OnDeviceLlmGateway gateway;

  /// 模型落盘路径（provider 已按快照判定 ready，此处**不触发下载**）。
  final Future<String> Function() modelPath;

  /// 图片归一化（复用拍照识别的 768 长边缩放；单测注入恒等实现）。
  final PhotoImageNormalizer normalizeImage;

  /// OOM 后永久禁用（与端侧拍照识别同策略）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  /// 识别阶段回调（识别中对话框据此切「加载模型 / 识别中」文案）。
  void Function(OnDeviceRecognitionPhase phase)? onPhaseChanged;

  @override
  Future<ExerciseScreenshotOutcome> recognize(Uint8List imageBytes) async {
    if (_permanentlyDisabled) {
      return const ExerciseScreenshotUnavailable('ondevice_disabled');
    }
    final Uint8List normalized;
    try {
      normalized = await normalizeImage(imageBytes);
    } on Object {
      return const ExerciseScreenshotUnavailable('bad_image');
    }
    try {
      if (!gateway.isLoaded || !gateway.visionEnabled) {
        onPhaseChanged?.call(OnDeviceRecognitionPhase.loadingModel);
        await gateway.load(await modelPath(), enableVision: true);
      }
      onPhaseChanged?.call(OnDeviceRecognitionPhase.inferring);
      final raw = await gateway.inferWithImage(
        buildExerciseScreenshotPrompt(),
        normalized,
        systemInstruction: kExerciseScreenshotSystemPrompt,
        maxOutputTokens: 192, // 单 JSON 对象，字段少，额度收紧
      );
      final data = parseExerciseScreenshotJson(raw);
      if (data == null) {
        // 含模型明说「无法识别」：透出原始回复（同拍照识别 parse_failed）。
        final detail = cleanRecognitionDetail(raw);
        return ExerciseScreenshotUnavailable(
          'parse_failed',
          detail: detail.isEmpty ? null : detail,
        );
      }
      return ExerciseScreenshotSuccess(data);
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return const ExerciseScreenshotUnavailable('ondevice_oom');
    } on OnDeviceLlmException {
      return const ExerciseScreenshotUnavailable('ondevice_error');
    } on Object {
      return const ExerciseScreenshotUnavailable('ondevice_error');
    }
  }
}
