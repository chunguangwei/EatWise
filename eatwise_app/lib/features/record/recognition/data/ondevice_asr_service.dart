/// 端侧 ASR 服务（Gemma 音频编码器转写）：PCM16→WAV 已由纯函数层封装，
/// 这里负责引擎加载契约（音频能力）+ 推理 + 输出清洗。
/// 任何失败返回 null（UI 回落降级：面板内错误态/权限降级卡）。
library;

import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';

/// 端侧语音转写服务（模型已下载且开关启用时由 onDeviceAsrServiceProvider
/// 提供；否则为 null，语音入口回落现有降级）。
final class OnDeviceAsrService {
  OnDeviceAsrService({required this.gateway, required this.modelPath});

  final OnDeviceLlmGateway gateway;

  /// 模型落盘路径（provider 已按快照判定，此处不触发下载）。
  final Future<String> Function() modelPath;

  /// OOM 后永久禁用（与拍照识别/端侧估算同策略）。
  bool _permanentlyDisabled = false;
  bool get isPermanentlyDisabled => _permanentlyDisabled;

  /// 转写 WAV 字节 → 清洗后文本；失败/空结果返回 null。
  Future<String?> transcribe(Uint8List wavBytes, {required bool isZh}) async {
    if (_permanentlyDisabled) return null;
    try {
      if (!gateway.isLoaded || !gateway.audioEnabled) {
        // 视觉+音频同时开：与拍照识别共用热引擎，避免能力配置来回重建
        //（重建一次数秒）。⚠️ E2B 若不含音频塔，此处加载失败 → null，
        // UI 面板显示错误态并可回落（AGENTS.md 已记录，需真机验证）。
        await gateway.load(
          await modelPath(),
          enableVision: true,
          enableAudio: true,
        );
      }
      final raw = await gateway.inferWithAudio(
        transcriptionPrompt(isZh),
        wavBytes,
        maxOutputTokens: 256, // 转写文本额度（一句话级别）
      );
      final text = cleanTranscriptionOutput(raw);
      return text.isEmpty ? null : text;
    } on OnDeviceLlmMemoryException {
      _permanentlyDisabled = true;
      return null;
    } on Object {
      return null; // 引擎/路径异常：静默降级
    }
  }
}
