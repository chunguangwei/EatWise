/// 端侧 ASR 服务（Gemma 音频编码器转写）：PCM16→WAV 已由纯函数层封装，
/// 这里负责引擎加载契约（音频能力）+ 推理 + 输出清洗。
/// 任何失败返回 null（UI 回落降级：面板内错误态/权限降级卡）。
library;

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';
import 'package:flutter/foundation.dart';

/// 端侧转写阶段（面板分阶段文案数据源，真实状态非假进度条）。
enum OnDeviceAsrStatus {
  /// 引擎加载中（首次冷加载/能力重建，数秒级）。
  loadingModel,

  /// 模型已就绪，正在转写。
  transcribing,
}

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

  /// 转写 WAV 字节 → 清洗后文本；失败/空结果返回 null（每条失败路径
  /// 都写 debugPrint 日志——真机「小模型不生效」排查依赖，不允许静默）。
  ///
  /// [onStatus] 阶段回调：需要加载引擎时先发 loadingModel，转写前发
  /// transcribing；已热引擎只发 transcribing。面板据此区分
  /// 「正在加载离线模型」与「转写中」两阶段文案（真实状态，非假进度条）。
  Future<String?> transcribe(
    Uint8List wavBytes, {
    required bool isZh,
    void Function(OnDeviceAsrStatus status)? onStatus,
  }) async {
    if (_permanentlyDisabled) {
      debugPrint('[OnDeviceAsr] 已永久禁用（此前 OOM），跳过转写');
      return null;
    }
    try {
      if (!gateway.isLoaded || !gateway.audioEnabled) {
        onStatus?.call(OnDeviceAsrStatus.loadingModel);
        // 视觉+音频同时开：与拍照识别共用热引擎，避免能力配置来回重建
        //（重建一次数秒）。⚠️ E2B 若不含音频塔，此处加载失败 → null，
        // UI 面板显示错误态并可回落（AGENTS.md 已记录，需真机验证）。
        debugPrint('[OnDeviceAsr] 加载引擎（enableVision+enableAudio）…');
        await gateway.load(
          await modelPath(),
          enableVision: true,
          enableAudio: true,
        );
      }
      onStatus?.call(OnDeviceAsrStatus.transcribing);
      final raw = await gateway.inferWithAudio(
        transcriptionPrompt(isZh),
        wavBytes,
        maxOutputTokens: 256, // 转写文本额度（一句话级别）
        // 采样参数沿用 yiren 真机调优值（低温+topK40+topP0.9，转写稳定性优先）。
        temperature: 0.1,
        topK: 40,
        topP: 0.9,
      );
      final text = cleanTranscriptionOutput(raw);
      if (text.isEmpty) {
        debugPrint('[OnDeviceAsr] 转写结果为空（清洗后无内容，原文 ${raw.length} 字符）');
        return null;
      }
      return text;
    } on OnDeviceLlmMemoryException catch (e) {
      debugPrint('[OnDeviceAsr] 转写失败：引擎内存不足，端侧 ASR 永久禁用（$e）');
      _permanentlyDisabled = true;
      return null;
    } on Object catch (e) {
      // 含音频塔缺失/引擎重建失败/路径异常——真机区分「不生效」根因靠这行。
      debugPrint('[OnDeviceAsr] 转写失败：${e.runtimeType} $e');
      return null;
    }
  }
}
