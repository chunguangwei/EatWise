import 'dart:typed_data';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
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
}

/// 推理网关 Fake（仅本测试需要的加载面）。
final class _FakeGateway implements OnDeviceLlmGateway {
  _FakeGateway({this.loaded = false, this.vision = false});

  bool loaded;
  bool vision;

  Object? loadError;
  int loadCalls = 0;
  bool? lastEnableVision;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  Future<void> load(String modelPath, {bool enableVision = false}) async {
    loadCalls++;
    lastEnableVision = enableVision;
    final error = loadError;
    if (error != null) throw error;
    loaded = true;
    vision = enableVision;
  }

  @override
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    throw UnimplementedError('预热测试不推理');
  }

  @override
  Future<String> inferWithImage(
    String prompt,
    Uint8List imageBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
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
