import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_asr_service.dart';
import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 端侧 ASR 转写服务单测（网关 Fake，不触碰真实引擎）。
///
/// 覆盖：转写成功 + 输出清洗、中文/英文 prompt 选择、清洗后为空 → null、
/// 引擎/解码失败 → null、OOM 永久禁用、音频能力加载契约
///（enableAudio: true + enableVision: true 共热引擎）、音频未加载拦截。
void main() {
  final wavBytes = Uint8List.fromList(<int>[82, 73, 70, 70, 1, 2, 3, 4]);

  /// debugPrint 捕获（防静默回归：失败路径必须留日志）。
  final logs = <String>[];
  late void Function(String?, {int? wrapWidth}) originalDebugPrint;

  setUp(() {
    logs.clear();
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  OnDeviceAsrService makeService(_FakeGateway gateway) {
    return OnDeviceAsrService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
    );
  }

  group('transcribe', () {
    test('转写成功：清洗引号/前缀后返回文本', () async {
      final gateway = _FakeGateway()..audioResponse = '转写结果：「一碗米饭」';
      final service = makeService(gateway);

      final text = await service.transcribe(wavBytes, isZh: true);

      expect(text, '一碗米饭');
      expect(gateway.lastPrompt, kTranscribePromptZh);
      expect(gateway.lastWav, wavBytes);
    });

    test('英文 prompt 选择（isZh=false）', () async {
      final gateway = _FakeGateway()..audioResponse = 'a bowl of rice';
      final service = makeService(gateway);

      final text = await service.transcribe(wavBytes, isZh: false);

      expect(text, 'a bowl of rice');
      expect(gateway.lastPrompt, kTranscribePromptEn);
    });

    test('清洗后为空 → null（UI 按失败处理）', () async {
      final gateway = _FakeGateway()..audioResponse = '  「」  ';
      final service = makeService(gateway);

      expect(await service.transcribe(wavBytes, isZh: true), isNull);
    });

    test('引擎推理失败 → null（静默降级）', () async {
      final gateway = _FakeGateway()
        ..inferError = const OnDeviceLlmEngineException('推理失败');
      final service = makeService(gateway);

      expect(await service.transcribe(wavBytes, isZh: true), isNull);
    });

    test('模型文件缺失 → null', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceModelMissingException('模型文件不存在');
      final service = makeService(gateway);

      expect(await service.transcribe(wavBytes, isZh: true), isNull);
    });

    test('OOM → null 且永久禁用（后续调用短路）', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final service = makeService(gateway);

      expect(await service.transcribe(wavBytes, isZh: true), isNull);
      expect(service.isPermanentlyDisabled, isTrue);
      expect(await service.transcribe(wavBytes, isZh: true), isNull);
      expect(gateway.loadCalls, 1); // 不再重试加载
    });

    test('onStatus 阶段回调：需加载 → loadingModel → transcribing', () async {
      final gateway = _FakeGateway()..audioResponse = '一碗米饭';
      final service = makeService(gateway);
      final statuses = <OnDeviceAsrStatus>[];

      await service.transcribe(wavBytes, isZh: true, onStatus: statuses.add);

      expect(statuses, <OnDeviceAsrStatus>[
        OnDeviceAsrStatus.loadingModel,
        OnDeviceAsrStatus.transcribing,
      ]);
    });

    test('onStatus 阶段回调：已热引擎只发 transcribing', () async {
      final gateway = _FakeGateway(loaded: true, audio: true, vision: true)
        ..audioResponse = '一碗米饭';
      final service = makeService(gateway);
      final statuses = <OnDeviceAsrStatus>[];

      await service.transcribe(wavBytes, isZh: true, onStatus: statuses.add);

      expect(statuses, <OnDeviceAsrStatus>[OnDeviceAsrStatus.transcribing]);
    });

    test('onStatus 为 null 时正常工作（回调可选）', () async {
      final gateway = _FakeGateway()..audioResponse = '一碗米饭';
      final service = makeService(gateway);

      expect(await service.transcribe(wavBytes, isZh: true), '一碗米饭');
    });

    test('音频能力加载契约：视觉+音频同开（与拍照识别共热引擎）', () async {
      final gateway = _FakeGateway()..audioResponse = '一碗米饭';
      final service = makeService(gateway);

      await service.transcribe(wavBytes, isZh: true);

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableAudio, isTrue);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('已带音频加载 → 幂等复用不重复加载', () async {
      final gateway = _FakeGateway(loaded: true, audio: true, vision: true)
        ..audioResponse = '一碗米饭';
      final service = makeService(gateway);

      await service.transcribe(wavBytes, isZh: true);

      expect(gateway.loadCalls, 0);
    });

    test('音频未启用时网关显式拦截（与视觉拦截同口径）', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..inferError = const OnDeviceLlmEngineException('当前模型未启用音频能力');
      final service = makeService(gateway);

      // 网关拦截抛 engine 异常 → 服务映射 null（降级）
      expect(await service.transcribe(wavBytes, isZh: true), isNull);
    });

    test('失败路径留日志：引擎错误/空结果/OOM 均有 debugPrint（防静默）', () async {
      // 引擎错误 → 带类型与消息的日志。
      final gateway = _FakeGateway()
        ..inferError = const OnDeviceLlmEngineException('音频塔加载失败');
      final service = makeService(gateway);
      await service.transcribe(wavBytes, isZh: true);
      expect(
        logs.any(
          (l) => l.contains('[OnDeviceAsr] 转写失败') && l.contains('音频塔加载失败'),
        ),
        isTrue,
        reason: '引擎失败必须写日志（真机「小模型不生效」排查依赖）',
      );

      // 清洗后为空 → 空结果日志。
      logs.clear();
      gateway.inferError = null;
      gateway.audioResponse = '「」';
      await service.transcribe(wavBytes, isZh: true);
      expect(logs.any((l) => l.contains('[OnDeviceAsr] 转写结果为空')), isTrue);

      // OOM → 永久禁用日志 + 后续短路日志（换新实例：原网关已加载，
      // 加载失败路径需要未加载状态）。
      logs.clear();
      final oomGateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final oomService = makeService(oomGateway);
      await oomService.transcribe(wavBytes, isZh: true);
      expect(logs.any((l) => l.contains('[OnDeviceAsr] 转写失败：引擎内存不足')), isTrue);
      logs.clear();
      await oomService.transcribe(wavBytes, isZh: true);
      expect(logs.any((l) => l.contains('已永久禁用')), isTrue);
    });
  });
}

/// 推理网关 Fake（音频路径；文本/视觉接口仅契约性占位）。
final class _FakeGateway implements OnDeviceLlmGateway {
  _FakeGateway({this.loaded = false, this.vision = false, this.audio = false});

  bool loaded;
  bool vision;
  bool audio;

  String audioResponse = '';
  Object? loadError;
  Object? inferError;
  int loadCalls = 0;
  bool? lastEnableVision;
  bool? lastEnableAudio;
  String? lastPrompt;
  Uint8List? lastWav;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  bool get audioEnabled => loaded && audio;

  @override
  Future<void> load(
    String modelPath, {
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
    loadCalls++;
    lastEnableVision = enableVision;
    lastEnableAudio = enableAudio;
    final error = loadError;
    if (error != null) throw error;
    loaded = true;
    vision = enableVision;
    audio = enableAudio;
  }

  @override
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    double? topP,
    int seed = 42,
  }) {
    throw UnimplementedError('本测试不走文本推理');
  }

  @override
  Future<String> inferWithImage(
    String prompt,
    Uint8List imageBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    double? topP,
    int seed = 42,
  }) {
    throw UnimplementedError('本测试不走视觉推理');
  }

  @override
  Future<String> inferWithAudio(
    String prompt,
    Uint8List wavBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    double? topP,
    int seed = 42,
  }) async {
    lastPrompt = prompt;
    lastWav = wavBytes;
    final error = inferError;
    if (error != null) throw error;
    return audioResponse;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
    audio = false;
  }
}
