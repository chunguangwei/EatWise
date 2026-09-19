import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// 引擎预热（设置页打开开关后的后台 load）：就绪判定、视觉能力加载、
/// 幂等复用、失败静默。
void main() {
  group('prewarmOnDeviceEngine', () {
    test('模型未就绪 → 不触碰引擎（不触发下载/加载）', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngine(
        modelPath: () async => throw StateError('不应取路径'),
        isModelReady: () => false,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 0);
    });

    test('就绪且未加载 → 以视觉能力后台加载（首拍即热）', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('就绪且已带视觉加载 → 幂等复用不重复加载', () async {
      final gateway = _FakeGateway(loaded: true, vision: true);

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 0);
    });

    test('加载失败 → 静默吞掉（使用路径会重试并走各自降级）', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');

      // 不抛即通过。
      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 1); // 尝试过，失败被吞
    });
  });

  group('enableAudio 参数（语音路径预热）', () {
    test('enableAudio: true → 视觉+音频同开加载', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
        enableAudio: true,
      );

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
      expect(gateway.lastEnableAudio, isTrue);
    });

    test('默认（不带 enableAudio）→ 保持视觉-only（向后兼容）', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
      expect(gateway.lastEnableAudio, isFalse);
    });

    test('已带视觉+音频加载 → enableAudio 也幂等跳过', () async {
      final gateway = _FakeGateway(loaded: true, vision: true, audio: true);

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
        enableAudio: true,
      );

      expect(gateway.loadCalls, 0);
    });

    test('已带视觉但无音频 + enableAudio → 补载（能力组合不齐）', () async {
      final gateway = _FakeGateway(loaded: true, vision: true);

      await prewarmOnDeviceEngine(
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
        enableAudio: true,
      );

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableAudio, isTrue);
    });
  });

  group('prewarmOnDeviceEngineOnStartup（冷启动预热编排）', () {
    test('快照 ready + 开关开 → 触发视觉预热（重启后首拍即热）', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngineOnStartup(
        firstSnapshot: Future<OnDeviceModelSnapshot>.value(
          const OnDeviceModelSnapshot(status: OnDeviceModelStatus.ready),
        ),
        isEnabled: () => true,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('快照 ready 但开关关 → 不预热', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngineOnStartup(
        firstSnapshot: Future<OnDeviceModelSnapshot>.value(
          const OnDeviceModelSnapshot(status: OnDeviceModelStatus.ready),
        ),
        isEnabled: () => false,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 0);
    });

    test('开关开但快照未下载 → 不预热', () async {
      final gateway = _FakeGateway();

      await prewarmOnDeviceEngineOnStartup(
        firstSnapshot: Future<OnDeviceModelSnapshot>.value(
          const OnDeviceModelSnapshot(
            status: OnDeviceModelStatus.notDownloaded,
          ),
        ),
        isEnabled: () => true,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => false,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 0);
    });

    test('快照流失败 → 静默吞掉不阻断启动', () async {
      final gateway = _FakeGateway();

      // 不抛即通过。
      await prewarmOnDeviceEngineOnStartup(
        firstSnapshot: Future<OnDeviceModelSnapshot>.error(
          StateError('refresh failed'),
        ),
        isEnabled: () => true,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        isModelReady: () => true,
        gateway: gateway,
      );

      expect(gateway.loadCalls, 0);
    });
  });
}

/// 推理网关 Fake（仅本测试需要的加载面）。
final class _FakeGateway implements OnDeviceLlmGateway {
  _FakeGateway({this.loaded = false, this.vision = false, this.audio = false});

  bool loaded;
  bool vision;
  bool audio;

  Object? loadError;
  int loadCalls = 0;
  bool? lastEnableVision;
  bool? lastEnableAudio;

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
    throw UnimplementedError('预热测试不推理');
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
  }) {
    throw UnimplementedError('本测试不走音频推理');
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
    throw UnimplementedError('预热测试不推理');
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}
