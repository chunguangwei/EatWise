import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:eatwise/features/record/recognition/voice/audio_recorder_gateway.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';

/// 取图 fake：可配置返回字节 / 用户取消（null）/ 权限拒绝。
final class FakePhotoPickerGateway implements PhotoPickerGateway {
  Uint8List? bytes = Uint8List.fromList(<int>[1, 2, 3]);
  bool throwDenied = false;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    if (throwDenied) throw PhotoPermissionDeniedException(source);
    return bytes;
  }
}

/// 识别服务 fake：固定结果或挂起（测「识别中可取消」）。
final class FakeFoodRecognitionService implements FoodRecognitionService {
  RecognitionOutcome outcome = const RecognitionUnavailable('not_integrated');
  Completer<RecognitionOutcome>? completer;

  @override
  Future<RecognitionOutcome> recognize(Uint8List imageBytes) {
    final pending = completer;
    if (pending != null) return pending.future;
    return Future<RecognitionOutcome>.value(outcome);
  }
}

/// 系统 ASR fake：可配置不可用（权限拒绝/设备不支持），
/// 暴露 onText 供测试模拟系统回传识别文本。
final class FakeSpeechGateway implements SpeechGateway {
  bool available = true;
  void Function(String text)? onText;
  void Function(String error)? onError;
  bool cancelled = false;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<void> start({
    required void Function(String text) onText,
    void Function(String error)? onError,
    required String localeId,
  }) async {
    this.onText = onText;
    this.onError = onError;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

/// 麦克风录音 fake（端侧 ASR 路径）：可配置权限拒绝 / 录音产出字节 / 取消标记。
final class FakeAudioRecorderGateway implements AudioRecorderGateway {
  bool permitted = true;
  Uint8List? pcm = Uint8List.fromList(<int>[1, 2, 3, 4]);
  bool recording = false;
  bool cancelled = false;

  @override
  Future<bool> ensurePermission() async => permitted;

  @override
  Future<void> start() async {
    recording = true;
  }

  @override
  Future<Uint8List?> stop() async {
    recording = false;
    return pcm;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    recording = false;
  }
}
