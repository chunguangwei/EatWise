import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:eatwise/features/social/application/post_polish_providers.dart';
import 'package:eatwise/features/social/application/post_polish_service.dart';
import 'package:eatwise/features/social/domain/post_polish_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 润色：纯函数清洗 / 端侧服务降级分支 / provider 门控。
void main() {
  group('cleanPolishResult', () {
    test('去首尾空白与整段包裹引号（中/英/弯引号）', () {
      expect(cleanPolishResult('  今天也完成了！  '), '今天也完成了！');
      expect(cleanPolishResult('"坚持的第 7 天"'), '坚持的第 7 天');
      expect(cleanPolishResult('「第 7 天打卡」'), '第 7 天打卡');
      expect(cleanPolishResult('\u{201C}打卡成功\u{201D}'), '打卡成功');
    });

    test('不成对的引号保留（不误删正文引号）', () {
      expect(cleanPolishResult('他说"加油'), '他说"加油');
    });

    test('去「润色后：」类前缀', () {
      expect(cleanPolishResult('润色后：第 7 天，稳稳的。'), '第 7 天，稳稳的。');
      expect(cleanPolishResult('润色结果：稳'), '稳');
    });

    test('超长截断到 maxChars', () {
      final long = '字' * 620;
      expect(cleanPolishResult(long).length, 500);
      expect(cleanPolishResult('abcdef', maxChars: 3), 'abc');
    });

    test('空输出清洗后仍为空（服务映射 empty_output）', () {
      expect(cleanPolishResult('  "  "  '), '');
    });
  });

  group('buildPostPolishPrompt', () {
    test('带图/不带图文案不同（带图提示参考画面）', () {
      expect(buildPostPolishPrompt('吃了沙拉'), contains('请润色下面这段打卡文案：\n「吃了沙拉」'));
      expect(buildPostPolishPrompt('吃了沙拉', hasImage: true), contains('配图'));
    });
  });

  group('OnDevicePostPolishService', () {
    test('纯文本润色：未加载 → load(文本模式) → infer → 清洗回填', () async {
      final gw = _FakeGateway();
      gw.inferReply = '润色后：「第 7 天，身体在谢谢你。」';
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      final phases = <PostPolishPhase>[];
      service.onPhaseChanged = phases.add;
      final result = await service.polish('第7天打卡');
      expect(result, isA<PostPolishOk>());
      expect((result as PostPolishOk).text, '第 7 天，身体在谢谢你。');
      expect(gw.loadCalls, 1);
      expect(gw.lastEnableVision, isFalse);
      expect(phases, <PostPolishPhase>[
        PostPolishPhase.loadingModel,
        PostPolishPhase.inferring,
      ]);
      expect(gw.lastPrompt, contains('第7天打卡'));
    });

    test('带图润色：走 inferWithImage 且 load 开视觉', () async {
      final gw = _FakeGateway(loaded: true, vision: true);
      gw.imageReply = '阳光下的沙拉，看着就健康。';
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      final result = await service.polish('吃了沙拉', imageBytes: _png);
      expect((result as PostPolishOk).text, '阳光下的沙拉，看着就健康。');
      expect(gw.loadCalls, 0); // 已加载且视觉就绪：不重载
      expect(gw.imageBytesPassed, _png);
      expect(gw.lastPrompt, contains('配图'));
    });

    test('已加载但无视觉能力 + 带图 → 以视觉重建', () async {
      final gw = _FakeGateway(loaded: true, vision: false);
      gw.imageReply = '好';
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      await service.polish('文本', imageBytes: _png);
      expect(gw.lastEnableVision, isTrue);
    });

    test('图片归一化失败 → 降级纯文本润色（不因图挂）', () async {
      final gw = _FakeGateway(loaded: true, vision: true);
      gw.inferReply = '纯文本也能润';
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
        normalizeImage: (_) async => throw StateError('decode fail'),
      );
      final result = await service.polish('文本', imageBytes: _png);
      expect((result as PostPolishOk).text, '纯文本也能润');
    });

    test('模型缺失 → model_missing（不永久禁用，可再试）', () async {
      final gw = _FakeGateway()
        ..loadError = const OnDeviceModelMissingException('no file');
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      expect(
        await service.polish('文本'),
        isA<PostPolishUnavailable>().having(
          (e) => e.reason,
          'reason',
          'model_missing',
        ),
      );
      // 第二次仍可尝试加载
      await service.polish('文本');
      expect(gw.loadCalls, 2);
    });

    test('OOM → 永久禁用（后续调用不再触碰引擎）', () async {
      final gw = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('oom');
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      expect(
        await service.polish('文本'),
        isA<PostPolishUnavailable>().having((e) => e.reason, 'reason', 'oom'),
      );
      expect(
        await service.polish('文本'),
        isA<PostPolishUnavailable>().having(
          (e) => e.reason,
          'reason',
          'ondevice_disabled',
        ),
      );
      expect(gw.loadCalls, 1);
    });

    test('引擎错误可重试；空输出 → empty_output', () async {
      final gw = _FakeGateway(loaded: true)
        ..inferReply = ''
        ..engineError = const OnDeviceLlmEngineException('boom');
      final service = OnDevicePostPolishService(
        gateway: gw,
        modelPath: () async => '/models/gemma.litertlm',
      );
      expect(
        await service.polish('文本'),
        isA<PostPolishUnavailable>().having(
          (e) => e.reason,
          'reason',
          'engine_error',
        ),
      );
      gw.engineError = null; // inferReply 空串 → empty_output
      expect(
        await service.polish('文本'),
        isA<PostPolishUnavailable>().having(
          (e) => e.reason,
          'reason',
          'empty_output',
        ),
      );
    });
  });

  group('postPolishServiceProvider 门控', () {
    Future<ProviderContainer> makeContainer({
      required bool enabled,
      required OnDeviceModelStatus status,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.onDeviceAiEnabled': enabled,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceModelSnapshotProvider.overrideWith(
            (ref) => Stream<OnDeviceModelSnapshot>.value(
              OnDeviceModelSnapshot(status: status),
            ),
          ),
          apiDioProvider.overrideWithValue(Dio()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('开关关 → null（UI 隐藏入口）', () async {
      final container = await makeContainer(
        enabled: false,
        status: OnDeviceModelStatus.ready,
      );
      await container.read(onDeviceModelSnapshotProvider.future);
      expect(container.read(postPolishServiceProvider), isNull);
    });

    test('快照明确未就绪 → null', () async {
      final container = await makeContainer(
        enabled: true,
        status: OnDeviceModelStatus.notDownloaded,
      );
      await container.read(onDeviceModelSnapshotProvider.future);
      expect(container.read(postPolishServiceProvider), isNull);
    });

    test('开关开 + 就绪 → 端侧服务实例', () async {
      final container = await makeContainer(
        enabled: true,
        status: OnDeviceModelStatus.ready,
      );
      await container.read(onDeviceModelSnapshotProvider.future);
      expect(
        container.read(postPolishServiceProvider),
        isA<OnDevicePostPolishService>(),
      );
    });
  });
}

final Uint8List _png = Uint8List.fromList(<int>[1, 2, 3, 4]);

/// 网关 Fake：记录加载参数/提示词，回复与异常可配置。
final class _FakeGateway implements OnDeviceLlmGateway {
  _FakeGateway({this.loaded = false, this.vision = false});

  bool loaded;
  bool vision;

  Object? loadError;
  Object? engineError;
  String inferReply = '';
  String imageReply = '';

  int loadCalls = 0;
  bool? lastEnableVision;
  String? lastPrompt;
  Uint8List? imageBytesPassed;

  @override
  bool get isLoaded => loaded;

  @override
  bool get visionEnabled => loaded && vision;

  @override
  bool get audioEnabled => false;

  @override
  Future<void> load(
    String modelPath, {
    bool enableVision = false,
    bool enableAudio = false,
  }) async {
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
    double? topP,
    int seed = 42,
  }) async {
    final error = engineError;
    if (error != null) throw error;
    lastPrompt = prompt;
    return inferReply;
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
  }) async {
    final error = engineError;
    if (error != null) throw error;
    lastPrompt = prompt;
    imageBytesPassed = imageBytes;
    return imageReply;
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
    throw UnimplementedError();
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}
