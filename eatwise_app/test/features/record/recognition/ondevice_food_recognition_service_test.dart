import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端侧视觉拍照识别服务单测（网关 Fake，不触碰真实引擎）。
///
/// 覆盖：成功精确/模糊命中、dubious 低置信、解析失败/库未命中/坏图降级、
/// OOM 永久禁用、引擎错误降级、视觉加载契约（enableVision: true 幂等）、
/// 以及 foodRecognitionServiceProvider 的选择逻辑（开关+就绪 → 端侧实现）。
void main() {
  final photoBytes = Uint8List.fromList(<int>[1, 2, 3]);

  Food food({required String id, required String zh, String en = ''}) => Food(
    id: id,
    nameZh: zh,
    nameEn: en,
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 23,
    fatPer100g: 0.3,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: 'req-$id',
  );

  OnDeviceFoodRecognitionService makeService({
    required _FakeGateway gateway,
    Map<String, List<Food>> searchResults = const <String, List<Food>>{},
    PhotoImageNormalizer? normalizeImage,
  }) {
    return OnDeviceFoodRecognitionService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
      searchFoods: (query) async => searchResults[query] ?? <Food>[],
      normalizeImage: normalizeImage ?? (bytes) async => bytes,
    );
  }

  group('recognize 成功路径', () {
    test('精确命中库：Top-1 用库内条目，置信 0.85，默认份量 100g', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => 116 => 2.6 => 23 => 0.3';
      final rice = food(id: 'f-rice', zh: '米饭', en: 'Rice');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [rice],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.candidates, hasLength(1));
      final top = success.candidates.first;
      expect(top.food.id, 'f-rice');
      expect(top.defaultAmountG, 100);
      expect(top.confidence, 0.85);
      expect(top.isLowConfidence, isFalse);
    });

    test('模糊命中库：成功但低置信（0.6 → 标「请确认」）', () async {
      final gateway = _FakeGateway()..response = '番茄炒鸡蛋 => 120 => 6 => 8 => 7';
      final matched = food(id: 'f-tomato-egg', zh: '西红柿炒鸡蛋');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '番茄炒鸡蛋': [matched],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.candidates.first.food.id, 'f-tomato-egg');
      expect(success.candidates.first.confidence, 0.6);
      expect(success.candidates.first.isLowConfidence, isTrue);
    });

    test('sanity-clamp 命中（宏量超限）→ 置信 0.5 标「请确认」', () async {
      // 蛋白质 70g/100g 触发 isNutritionEstimateDubious 规则 1。
      final gateway = _FakeGateway()..response = '炸鸡 => 300 => 70 => 5 => 10';
      final fried = food(id: 'f-fried', zh: '炸鸡');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '炸鸡': [fried],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.candidates.first.confidence, 0.5);
      expect(success.candidates.first.isLowConfidence, isTrue);
    });

    test('prompt/系统提示词按视觉版模板传递', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => 116 => 2.6 => 23 => 0.3';
      final rice = food(id: 'f-rice', zh: '米饭');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [rice],
        },
      );

      await service.recognize(photoBytes);

      expect(gateway.lastPrompt, buildPhotoRecognitionPrompt());
      expect(gateway.lastSystemInstruction, kPhotoRecognitionSystemPrompt);
      expect(gateway.lastImage, photoBytes);
    });
  });

  group('降级路径（一律 RecognitionUnavailable，与 UI 兜底兼容）', () {
    test('模型输出「无法识别」→ parse_failed', () async {
      final gateway = _FakeGateway()..response = '无法识别';
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      expect((outcome as RecognitionUnavailable).reason, 'parse_failed');
    });

    test('识别名映射不回食物库 → no_match（估值不入账）', () async {
      final gateway = _FakeGateway()..response = '外星食物 => 100 => 5 => 10 => 2';
      final service = makeService(gateway: gateway); // 搜索恒空

      final outcome = await service.recognize(photoBytes);

      expect((outcome as RecognitionUnavailable).reason, 'no_match');
    });

    test('图片解码失败 → bad_image（不触发推理）', () async {
      final gateway = _FakeGateway();
      final service = makeService(
        gateway: gateway,
        normalizeImage: (_) async => throw StateError('decode failed'),
      );

      final outcome = await service.recognize(photoBytes);

      expect((outcome as RecognitionUnavailable).reason, 'bad_image');
      expect(gateway.inferCalls, 0);
    });

    test('加载 OOM → ondevice_oom，且后续调用永久短路', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final service = makeService(gateway: gateway);

      final first = await service.recognize(photoBytes);
      expect((first as RecognitionUnavailable).reason, 'ondevice_oom');
      expect(service.isPermanentlyDisabled, isTrue);

      final second = await service.recognize(photoBytes);
      expect((second as RecognitionUnavailable).reason, 'ondevice_disabled');
      expect(gateway.loadCalls, 1); // 不再重试加载
    });

    test('推理 OOM → 同样永久禁用', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..inferError = const OnDeviceLlmMemoryException('推理过程内存不足');
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      expect((outcome as RecognitionUnavailable).reason, 'ondevice_oom');
      expect(service.isPermanentlyDisabled, isTrue);
    });

    test('引擎错误 → ondevice_error（可重试，不永久禁用）', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..inferError = const OnDeviceLlmEngineException('推理失败');
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      expect((outcome as RecognitionUnavailable).reason, 'ondevice_error');
      expect(service.isPermanentlyDisabled, isFalse);
    });
  });

  group('视觉加载契约', () {
    test('未加载 → 以 enableVision: true 加载一次', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );

      await service.recognize(photoBytes);

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('已加载但无视觉 → 重新以视觉能力加载', () async {
      final gateway = _FakeGateway(loaded: true)
        ..response = '米饭 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );

      await service.recognize(photoBytes);

      expect(gateway.loadCalls, 1);
      expect(gateway.lastEnableVision, isTrue);
    });

    test('已带视觉加载 → 幂等复用不重复加载', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..response = '米饭 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );

      await service.recognize(photoBytes);

      expect(gateway.loadCalls, 0);
    });
  });

  group('foodRecognitionServiceProvider 选择逻辑', () {
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

    test('开关关 → 远端 stub（即便模型就绪）', () async {
      final container = await makeContainer(
        enabled: false,
        status: OnDeviceModelStatus.ready,
      );
      expect(
        container.read(foodRecognitionServiceProvider),
        isA<RemoteFoodRecognitionStub>(),
      );
    });

    test('开关开但模型未下载 → 远端 stub', () async {
      final container = await makeContainer(
        enabled: true,
        status: OnDeviceModelStatus.notDownloaded,
      );
      expect(
        container.read(foodRecognitionServiceProvider),
        isA<RemoteFoodRecognitionStub>(),
      );
    });

    test('开关开且模型就绪 → 端侧视觉实现', () async {
      final container = await makeContainer(
        enabled: true,
        status: OnDeviceModelStatus.ready,
      );
      // 状态流首发前回退管理器快照（notDownloaded）；等流发出 ready 后重建。
      await container.read(onDeviceModelSnapshotProvider.future);
      expect(
        container.read(foodRecognitionServiceProvider),
        isA<OnDeviceFoodRecognitionService>(),
      );
    });
  });
}

/// 推理网关 Fake：记录调用契约，可注入加载/推理错误。
final class _FakeGateway implements OnDeviceLlmGateway {
  _FakeGateway({this.loaded = false, this.vision = false});

  bool loaded;
  bool vision;

  String response = '';
  Object? loadError;
  Object? inferError;
  int loadCalls = 0;
  int inferCalls = 0;
  bool? lastEnableVision;
  String? lastPrompt;
  Uint8List? lastImage;
  String? lastSystemInstruction;

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
    throw UnimplementedError('本测试只走视觉推理');
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
  }) async {
    inferCalls++;
    lastPrompt = prompt;
    lastImage = imageBytes;
    lastSystemInstruction = systemInstruction;
    final error = inferError;
    if (error != null) throw error;
    return response;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}
