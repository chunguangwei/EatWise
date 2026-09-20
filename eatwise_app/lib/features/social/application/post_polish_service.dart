import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/social/domain/post_polish_logic.dart';

/// 润色结果（sealed，UI 按分支反馈）。
sealed class PostPolishResult {
  const PostPolishResult();
}

final class PostPolishOk extends PostPolishResult {
  const PostPolishOk(this.text);
  final String text;
}

/// 不可用/失败（原因码仅埋点用；UI 统一「润色失败」提示）。
final class PostPolishUnavailable extends PostPolishResult {
  const PostPolishUnavailable(this.reason);
  final String reason;
}

/// 端侧润色阶段（UI 进度文案：加载模型 vs 推理）。
enum PostPolishPhase { loadingModel, inferring }

/// 润色服务接口（测试注入 Fake）。
abstract interface class PostPolishService {
  /// 阶段回调（调 [polish] 前挂上，用完置 null）。
  set onPhaseChanged(void Function(PostPolishPhase phase)? cb);

  /// 润色 [text]；[imageBytes] 为已选配图（null → 纯文本润色）。
  Future<PostPolishResult> polish(String text, {Uint8List? imageBytes});
}

/// 端侧 Gemma4-E2B 润色服务：网关加载/降级模式与拍照识别服务
/// （OnDeviceFoodRecognitionService）同款——OOM 永久禁用，其余失败可重试；
/// 有配图走视觉（inferWithImage），无配图退化为纯文本 infer。
final class OnDevicePostPolishService implements PostPolishService {
  OnDevicePostPolishService({
    required this.gateway,
    required this.modelPath,
    this.normalizeImage,
  });

  final OnDeviceLlmGateway gateway;
  final Future<String> Function() modelPath;

  /// 配图下采样（复用拍照识别归一化；null = 原图直送）。
  final Future<Uint8List> Function(Uint8List bytes)? normalizeImage;

  bool _permanentlyDisabled = false;

  @override
  void Function(PostPolishPhase phase)? onPhaseChanged;

  @override
  Future<PostPolishResult> polish(String text, {Uint8List? imageBytes}) async {
    if (_permanentlyDisabled) {
      return const PostPolishUnavailable('ondevice_disabled');
    }
    Uint8List? image;
    if (imageBytes != null) {
      try {
        image = normalizeImage == null
            ? imageBytes
            : await normalizeImage!(imageBytes);
      } on Object {
        // 图片解码失败：降级为纯文本润色（润色主流程不因图挂）。
        image = null;
      }
    }
    try {
      // 视觉重建判定同款：模型缺视觉能力却带图推理，插件会静默丢图。
      if (!gateway.isLoaded || (image != null && !gateway.visionEnabled)) {
        onPhaseChanged?.call(PostPolishPhase.loadingModel);
        await gateway.load(await modelPath(), enableVision: image != null);
      }
      onPhaseChanged?.call(PostPolishPhase.inferring);
      final raw = image == null
          ? await gateway.infer(
              buildPostPolishPrompt(text),
              systemInstruction: kPostPolishSystemPrompt,
              maxOutputTokens: 256,
            )
          : await gateway.inferWithImage(
              buildPostPolishPrompt(text, hasImage: true),
              image,
              systemInstruction: kPostPolishSystemPrompt,
              maxOutputTokens: 256,
            );
      final cleaned = cleanPolishResult(raw);
      if (cleaned.isEmpty) {
        return const PostPolishUnavailable('empty_output');
      }
      return PostPolishOk(cleaned);
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return const PostPolishUnavailable('oom');
    } on OnDeviceModelMissingException {
      return const PostPolishUnavailable('model_missing');
    } on OnDeviceLlmException {
      return const PostPolishUnavailable('engine_error');
    } on Object {
      return const PostPolishUnavailable('unknown');
    }
  }
}
