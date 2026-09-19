import 'dart:async';
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
/// 覆盖：多行明细（组合餐多条/克数 clamp/库命中用库内每100g）、
/// 库未命中条目保留模型估值标低置信、dubious/类别词低置信、
/// 解析失败/坏图降级、OOM 永久禁用、引擎错误降级、视觉加载契约、
/// 识别阶段回调、foodRecognitionServiceProvider 选择逻辑。
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

  group('recognize 成功路径（多行明细）', () {
    test('单食物七段：克数/每100g/置信 0.85，库内精准值入账口径', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
      final rice = food(id: 'f-rice', zh: '米饭', en: 'Rice');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [rice],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.items, hasLength(1));
      final item = success.items.single;
      expect(item.food!.id, 'f-rice');
      expect(item.isMatched, isTrue);
      expect(item.grams, 200); // 模型估份量预填（不再恒 100g）
      expect(item.per100g.kcal, 116); // 库内精准值
      expect(item.confidence, 0.85);
      expect(item.isLowConfidence, isFalse);
    });

    test('组合餐三行明细：逐条候选、克数各自独立、逐项库匹配', () async {
      final gateway = _FakeGateway()
        ..response =
            '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3\n'
            '鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8\n'
            '火腿 => ham => 30 => 145 => 16 => 2 => 8';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭', en: 'Rice')],
          '鸡蛋': [food(id: 'f-egg', zh: '鸡蛋', en: 'Egg')],
          // 火腿库未命中：保留模型估值
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.items, hasLength(3));
      expect(success.items[0].food!.id, 'f-rice');
      expect(success.items[0].grams, 200);
      expect(success.items[1].food!.id, 'f-egg');
      expect(success.items[1].grams, 50);
      final ham = success.items[2];
      expect(ham.isMatched, isFalse);
      expect(ham.name, '火腿');
      expect(ham.nameEn, 'ham');
      expect(ham.grams, 30);
      expect(ham.per100g.kcal, 145); // 模型估值
      expect(ham.confidence, 0.4); // 库未命中必低置信
      expect(ham.isLowConfidence, isTrue);
    });

    test('模糊命中库：成功但低置信（0.6 → 标「请确认」）', () async {
      final gateway = _FakeGateway()
        ..response =
            '番茄炒鸡蛋 => tomato egg stir-fry => 150 => 120 => 6 => 8 => 7';
      final matched = food(id: 'f-tomato-egg', zh: '西红柿炒鸡蛋');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '番茄炒鸡蛋': [matched],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.food!.id, 'f-tomato-egg');
      expect(item.confidence, 0.6);
      expect(item.isLowConfidence, isTrue);
    });

    test('sanity-clamp 命中（宏量超限）→ 置信 0.5 标「请确认」', () async {
      // 蛋白质 70g/100g 触发 isNutritionEstimateDubious 规则 1。
      final gateway = _FakeGateway()
        ..response = '炸鸡 => fried chicken => 200 => 300 => 70 => 5 => 10';
      final fried = food(id: 'f-fried', zh: '炸鸡');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '炸鸡': [fried],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.confidence, 0.5);
      expect(item.isLowConfidence, isTrue);
    });

    test('克数越界 → clamp 回区间并按可疑标低置信', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 3000 => 116 => 2.6 => 23 => 0.3';
      final rice = food(id: 'f-rice', zh: '米饭', en: 'Rice');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [rice],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.grams, 2000); // clamp 到上限
      expect(item.confidence, 0.5);
      expect(item.isLowConfidence, isTrue);
    });

    test('兼容输出无克数（六段/五段）→ 份量默认 100g', () async {
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

      expect((outcome as RecognitionSuccess).items.single.grams, 100);
    });

    test('prompt/系统提示词按视觉版模板传递', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
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
    test('模型输出「无法识别」→ parse_failed，detail 透出原文', () async {
      final gateway = _FakeGateway()..response = '无法识别';
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      final unavailable = outcome as RecognitionUnavailable;
      expect(unavailable.reason, 'parse_failed');
      expect(unavailable.detail, '无法识别');
    });

    test('parse_failed 的 detail 去换行并截断（80 字符 + …）', () async {
      final gateway = _FakeGateway()
        ..response = '这张照片里似乎没有食物，\n只有一张${'很长的桌' * 20}子。';
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      final unavailable = outcome as RecognitionUnavailable;
      expect(unavailable.reason, 'parse_failed');
      final detail = unavailable.detail!;
      expect(detail, isNot(contains('\n')));
      expect(detail.length, kRecognitionDetailMaxLength + 1);
      expect(detail, endsWith('…'));
    });

    test('单行损坏不拖垮整体：坏行跳过、好行照常', () async {
      final gateway = _FakeGateway()
        ..response =
            '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3\n'
            '坏行没有数字\n';
      final rice = food(id: 'f-rice', zh: '米饭', en: 'Rice');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [rice],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final success = outcome as RecognitionSuccess;
      expect(success.items, hasLength(1));
      expect(success.items.single.name, '米饭');
    });

    test('图片解码失败 → bad_image，detail 为空（不触发推理）', () async {
      final gateway = _FakeGateway();
      final service = makeService(
        gateway: gateway,
        normalizeImage: (_) async => throw StateError('decode failed'),
      );

      final outcome = await service.recognize(photoBytes);

      final unavailable = outcome as RecognitionUnavailable;
      expect(unavailable.reason, 'bad_image');
      expect(unavailable.detail, isNull);
      expect(gateway.inferCalls, 0);
    });

    test('加载 OOM → ondevice_oom（detail 为空），且后续调用永久短路', () async {
      final gateway = _FakeGateway()
        ..loadError = const OnDeviceLlmMemoryException('引擎加载内存不足');
      final service = makeService(gateway: gateway);

      final first = await service.recognize(photoBytes);
      expect((first as RecognitionUnavailable).reason, 'ondevice_oom');
      expect(first.detail, isNull);
      expect(service.isPermanentlyDisabled, isTrue);

      final second = await service.recognize(photoBytes);
      expect((second as RecognitionUnavailable).reason, 'ondevice_disabled');
      expect(second.detail, isNull);
      expect(gateway.loadCalls, 1); // 不再重试加载
    });

    test('推理 OOM → 同样永久禁用', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..inferError = const OnDeviceLlmMemoryException('推理过程内存不足');
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      final unavailable = outcome as RecognitionUnavailable;
      expect(unavailable.reason, 'ondevice_oom');
      expect(unavailable.detail, isNull);
      expect(service.isPermanentlyDisabled, isTrue);
    });

    test('引擎错误 → ondevice_error（detail 为空，可重试不永久禁用）', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..inferError = const OnDeviceLlmEngineException('推理失败');
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      final unavailable = outcome as RecognitionUnavailable;
      expect(unavailable.reason, 'ondevice_error');
      expect(unavailable.detail, isNull);
      expect(service.isPermanentlyDisabled, isFalse);
    });
  });

  group('视觉加载契约', () {
    test('未加载 → 以 enableVision: true 加载一次', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
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
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
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
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
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

  group('识别阶段回调（两阶段文案数据源）', () {
    test('引擎未加载 → loadingModel → inferring 依次上报', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );
      final phases = <OnDeviceRecognitionPhase>[];
      service.onPhaseChanged = phases.add;

      await service.recognize(photoBytes);

      expect(phases, <OnDeviceRecognitionPhase>[
        OnDeviceRecognitionPhase.loadingModel,
        OnDeviceRecognitionPhase.inferring,
      ]);
    });

    test('已带视觉加载 → 只上报 inferring（无加载阶段）', () async {
      final gateway = _FakeGateway(loaded: true, vision: true)
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );
      final phases = <OnDeviceRecognitionPhase>[];
      service.onPhaseChanged = phases.add;

      await service.recognize(photoBytes);

      expect(phases, <OnDeviceRecognitionPhase>[
        OnDeviceRecognitionPhase.inferring,
      ]);
    });

    test('未挂回调 → 正常完成（回调为可选项）', () async {
      final gateway = _FakeGateway()
        ..response = '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '米饭': [food(id: 'f-rice', zh: '米饭')],
        },
      );

      final outcome = await service.recognize(photoBytes);

      expect(outcome, isA<RecognitionSuccess>());
    });
  });

  group('双语输出与类别词黑名单', () {
    test('中文未命中 → 英文名回退命中库：成功 + 精确置信 0.85', () async {
      final gateway = _FakeGateway()
        ..response = '薯片 => potato chips => 60 => 536 => 7 => 53 => 32';
      final chips = food(id: 'f-chips', zh: '薯片（油炸）', en: 'potato chips');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          'potato chips': [chips],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.food!.id, 'f-chips');
      expect(item.name, '薯片（油炸）'); // 库内规范名
      expect(item.confidence, 0.85);
    });

    test('类别词即便精确命中库 → 置信 0.5 必标「请确认」', () async {
      final gateway = _FakeGateway()
        ..response = '水果 => fruit => 80 => 60 => 0.5 => 14 => 0.2';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '水果': [food(id: 'f-fruit', zh: '水果')],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.confidence, 0.5);
      expect(item.isLowConfidence, isTrue);
    });

    test('「水果捞」不误伤：具体名精确命中 → 0.85 高置信', () async {
      final gateway = _FakeGateway()
        ..response = '水果捞 => fruit salad => 150 => 90 => 1 => 20 => 0.5';
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '水果捞': [food(id: 'f-fruit-lao', zh: '水果捞')],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.confidence, 0.85);
      expect(item.isLowConfidence, isFalse);
    });
  });

  group('包装营养表照抄（fromLabel）', () {
    test('标签行未命中库：标签值入账口径保留 + 置信 0.6（请确认警告通道）', () async {
      final gateway = _FakeGateway()
        ..response =
            '清叶堂洋芋片 => potato chips => 50 => 2141 kJ => 6.1 => 53.0 => 30.7';
      final service = makeService(gateway: gateway); // 搜索恒空

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.isMatched, isFalse);
      expect(item.fromLabel, isTrue);
      expect(item.name, '清叶堂洋芋片'); // 品牌加品名
      expect(item.grams, 50); // 净含量直填
      expect(item.per100g.kcal, closeTo(511.7, 0.1)); // 标签值（kJ 已换算）
      expect(item.confidence, 0.6);
      expect(item.isLowConfidence, isTrue); // 警告通道：请确认徽标
    });

    test('标签行命中库：库内精准值 + 置信 0.9（标签+库双确认）', () async {
      final gateway = _FakeGateway()
        ..response =
            '薯片 => potato chips => 50 => 2141 kJ => 6.1 => 53.0 => 30.7';
      final chips = food(id: 'f-chips', zh: '薯片', en: 'potato chips');
      final service = makeService(
        gateway: gateway,
        searchResults: <String, List<Food>>{
          '薯片': [chips],
        },
      );

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.fromLabel, isTrue);
      expect(item.per100g.kcal, 116); // 命中用库内值（food() 默认 116）
      expect(item.confidence, 0.9);
      expect(item.isLowConfidence, isFalse);
    });

    test('标签值 sanity-clamp 不降级：宏量超限的标签行不被压到 0.5', () async {
      // 蛋白质 70g/100g 的极端标签（肉干类确实可能高超限线）：
      // ground truth 只警告不覆盖——不走 dubious 0.5 降级。
      final gateway = _FakeGateway()
        ..response = '牛肉干 => beef jerky => 80 => 1500 kJ => 70 => 5 => 10';
      final service = makeService(gateway: gateway);

      final outcome = await service.recognize(photoBytes);

      final item = (outcome as RecognitionSuccess).items.single;
      expect(item.fromLabel, isTrue);
      expect(item.per100g.proteinG, 70); // 数值不改写
      expect(item.confidence, 0.6); // 未命中档，不是 0.5 的 dubious 档
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
      // 快照未出首帧的窗口期乐观选端侧（冷启动竞态修复）；等流发出
      // notDownloaded 后按磁盘实况回退 stub。
      await container.read(onDeviceModelSnapshotProvider.future);
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

    test('冷启动竞态回归：开关开 + 快照未出首帧 → 仍选端侧（不落 stub）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.onDeviceAiEnabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      // 快照流悬挂不出首帧（模拟冷启动磁盘 refresh 进行中）。
      final pending = StreamController<OnDeviceModelSnapshot>();
      addTearDown(pending.close);
      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceModelSnapshotProvider.overrideWith((ref) => pending.stream),
          apiDioProvider.overrideWithValue(Dio()),
        ],
      );
      addTearDown(container.dispose);

      // 首帧未出也立即选端侧：真实就绪由服务内部 load 把关。
      expect(
        container.read(foodRecognitionServiceProvider),
        isA<OnDeviceFoodRecognitionService>(),
      );

      // 快照落地为未下载 → 重建回 stub。
      pending.add(
        const OnDeviceModelSnapshot(status: OnDeviceModelStatus.notDownloaded),
      );
      await container.read(onDeviceModelSnapshotProvider.future);
      expect(
        container.read(foodRecognitionServiceProvider),
        isA<RemoteFoodRecognitionStub>(),
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
  bool get audioEnabled => false; // 本用例不走音频

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
  }) {
    throw UnimplementedError('本测试只走视觉推理');
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
