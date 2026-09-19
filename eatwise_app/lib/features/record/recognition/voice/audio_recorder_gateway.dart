/// 麦克风录音抽象（端侧 ASR 用；record 插件封装，widget 测试注入 Fake）。
///
/// 录音规格统一 16kHz 单声道 PCM16（[kOnDeviceAsrSampleRate]），
/// 实现侧自管临时文件生命周期；WAV 封装在 Dart 纯函数层
///（ondevice_asr_logic.wrapPcm16AsWav）——LiteRT-LM 音频输入按 WAV bytes。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 录音网关（窄接口；实现见 [RecordAudioRecorderGateway]）。
abstract interface class AudioRecorderGateway {
  /// 麦克风权限（request=true 时按需申请；合规 §3：首次点语音入口时申请）。
  /// 返回 false = 拒绝（UI 走权限降级卡）。
  Future<bool> ensurePermission();

  /// 开始录音（16kHz 单声道 PCM16 裸数据，实现侧自管落盘路径）。
  Future<void> start();

  /// 停止录音并返回裸 PCM 字节（取消过/无有效录音返回 null）。
  Future<Uint8List?> stop();

  /// 取消录音（丢弃本次，不留文件）。
  Future<void> cancel();
}

/// record 插件实现（生产路径；pub.dev `record` 7.1.1：Android AudioRecord /
/// iOS AVFoundation，无原生额外依赖，minSdk 23 满足项目 26 基线）。
final class RecordAudioRecorderGateway implements AudioRecorderGateway {
  RecordAudioRecorderGateway({
    AudioRecorder? recorder,
    Future<Directory> Function()? tempDir,
  }) : _recorder = recorder ?? AudioRecorder(),
       _tempDir = tempDir ?? getTemporaryDirectory;

  final AudioRecorder _recorder;
  final Future<Directory> Function() _tempDir;

  @override
  Future<bool> ensurePermission() async {
    try {
      return await _recorder.hasPermission(request: true);
    } on Object {
      return false; // 平台通道异常按拒绝处理，走降级
    }
  }

  @override
  Future<void> start() async {
    final dir = await _tempDir();
    final active =
        '${dir.path}/eatwise_asr_${DateTime.now().microsecondsSinceEpoch}.pcm';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits, // 裸 PCM16，WAV 头由 Dart 层封装
        sampleRate: kOnDeviceAsrSampleRate,
        numChannels: kOnDeviceAsrNumChannels,
      ),
      path: active,
    );
  }

  @override
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null; // 读不到按无有效录音处理
    } finally {
      // 临时文件即用即删（WAV 由 Dart 层即时封装，不留垃圾）。
      try {
        await File(path).delete();
      } on Object {
        // 删除失败静默（系统临时目录，后续会被 OS 清理）
      }
    }
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  /// 释放原生资源（provider onDispose 调用）。
  Future<void> dispose() => _recorder.dispose();
}
