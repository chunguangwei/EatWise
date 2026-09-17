import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 识别不可用对话框 widget 测试：detail 非空 → 对话框透出模型内容
/// （不再是一闪而过的 snackbar）；detail 为空 → 保持 snackbar 兜底。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late RecordRepository repository;
  late FakePhotoPickerGateway photoGateway;
  late FakeFoodRecognitionService recognitionService;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    recordRemote = FakeRecordRemote();
    repository = RecordRepository(
      db: db,
      remote: recordRemote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    photoGateway = FakePhotoPickerGateway();
    recognitionService = FakeFoodRecognitionService();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  Future<void> settleUi(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffolds = find.byType(Scaffold);
    if (scaffolds.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(
        tester.element(scaffolds.first),
      ).hideCurrentSnackBar();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    FakeCustomFoodRemote? customRemote,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(FakeSpeechGateway()),
          if (customRemote != null)
            customFoodRemoteProvider.overrideWithValue(customRemote),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 走一遍「拍照记 → 拍照」，等待识别结果落地。
  Future<void> pickPhotoAndRecognize(WidgetTester tester) async {
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('模型回复「无法识别」：对话框透出原文 + 引导语，「知道了」关闭', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'parse_failed',
      detail: '无法识别',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    // 对话框：标题「未识别到食物」+ 模型原文引用 + 引导语。
    expect(find.text('未识别到食物'), findsOneWidget);
    expect(find.text('无法识别'), findsOneWidget);
    expect(find.text('换个角度拍，或手动搜索试试'), findsOneWidget);
    // 不再走 snackbar 兜底话术。
    expect(find.text('暂时识别不了，手动搜索一样快'), findsNothing);

    // 「知道了」关闭对话框，回到记录页（手动搜索路径不阻断）。
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未识别到食物'), findsNothing);
    expect(find.text('拍照记'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('模型原文多行/啰嗦：detail 按清理后单行展示', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'parse_failed',
      detail: '这张照片里似乎没有食物， 只有一张桌子',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    expect(find.text('未识别到食物'), findsOneWidget);
    expect(find.text('这张照片里似乎没有食物， 只有一张桌子'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await settleUi(tester);
  });

  testWidgets('识别出库外食物：对话框透出识别名 + 库未收录引导', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'no_match',
      detail: '外星食物',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    expect(find.text('识别为「外星食物」'), findsOneWidget);
    expect(find.text('食物库暂未收录这种食物，换个关键词手动搜索试试'), findsOneWidget);
    expect(find.text('未识别到食物'), findsNothing);

    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识别为「外星食物」'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('detail 为空的降级（bad_image 等）：保持 snackbar 兜底', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable('bad_image');
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    expect(find.text('暂时识别不了，手动搜索一样快'), findsOneWidget);
    expect(find.text('未识别到食物'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('「重新拍摄」：关闭对话框并重新拉起来源选择', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'parse_failed',
      detail: '无法识别',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);
    expect(find.text('未识别到食物'), findsOneWidget);

    await tester.tap(find.text('重新拍摄'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 来源选择底部面板重新出现（完整入口流程重来一遍）。
    expect(find.text('未识别到食物'), findsNothing);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);

    // 走完第二遍（拍照 → 仍无法识别 → 对话框再现 → 知道了关闭），
    // 不留悬挂的底部面板/路由。
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('未识别到食物'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未识别到食物'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('未识别对话框「手动搜索」：关闭并对焦搜索框（无预填）', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'parse_failed',
      detail: '无法识别',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);

    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('未识别到食物'), findsNothing);
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.focusNode!.hasFocus, isTrue);
    expect(searchField.controller!.text, isEmpty); // 无识别名，不预填
    await settleUi(tester);
  });

  testWidgets('库未收录对话框「手动搜索」：识别名预填进搜索框并对焦', (tester) async {
    recognitionService.outcome = const RecognitionUnavailable(
      'no_match',
      detail: '外星食物',
    );
    await pumpPage(tester);
    await pickPhotoAndRecognize(tester);
    expect(find.text('识别为「外星食物」'), findsOneWidget);

    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('识别为「外星食物」'), findsNothing);
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.controller!.text, '外星食物');
    expect(searchField.focusNode!.hasFocus, isTrue);
    // query 状态同步（搜索列表按预填词触发）。
    final pageContext = tester.element(find.byType(RecordPage));
    expect(
      ProviderScope.containerOf(pageContext).read(recordSearchQueryProvider),
      '外星食物',
    );
    await settleUi(tester);
  });

  testWidgets('识别超时：按 timeout 降级走 snackbar，加载框不无限转圈', (tester) async {
    recognitionService.completer = Completer<RecognitionOutcome>(); // 永不完成
    await pumpPage(tester);

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识别中…'), findsOneWidget);

    // 推进假时钟越过超时时长。
    await tester.pump(kPhotoRecognitionTimeout + const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('识别中…'), findsNothing);
    expect(find.text('暂时识别不了，手动搜索一样快'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('两阶段文案：加载/视觉重建 →「正在加载视觉模型…」，推理 →「识别中…」', (tester) async {
    // 真实端侧服务 + 可控网关：挂起 load / infer 分别断言两阶段文案。
    final gateway = _ControllableGateway();
    final onDeviceService = OnDeviceFoodRecognitionService(
      gateway: gateway,
      modelPath: () async => '/fake/gemma4-e2b.litertlm',
      searchFoods: (_) async => <Food>[],
      normalizeImage: (bytes) async => bytes,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(onDeviceService),
          speechGatewayProvider.overrideWithValue(FakeSpeechGateway()),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 加载/视觉重建阶段（load 挂起中）→ 加载模型文案，不是「识别中…」。
    expect(gateway.loadCalled, isTrue);
    expect(find.text('正在加载视觉模型…'), findsOneWidget);
    expect(find.text('识别中…'), findsNothing);

    // 加载完成 → 推理阶段（infer 挂起中）→ 识别中文案。
    gateway.completeLoad();
    await tester.pump();
    expect(gateway.inferCalled, isTrue);
    expect(find.text('识别中…'), findsOneWidget);
    expect(find.text('正在加载视觉模型…'), findsNothing);

    // 推理完成（无法识别）→ 加载框关闭，detail 对话框出现。
    gateway.completeInfer('无法识别');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('未识别到食物'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settleUi(tester);
  });

  testWidgets('「以估算值添加」：预填自定义食物表单（徽标），保存入本地库后可入账', (tester) async {
    // 放大测试屏幕：自定义食物弹层字段多，默认尺寸保存按钮不可点。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final customRemote = FakeCustomFoodRemote();
    recognitionService.outcome = const RecognitionUnavailable(
      'no_match',
      detail: '薯片',
      estimate: RecognizedFoodEstimate(
        name: '薯片',
        nameEn: 'potato chips',
        per100g: OnDeviceNutritionValues(
          kcal: 536,
          proteinG: 7,
          carbsG: 53,
          fatG: 32,
        ),
        lowConfidence: true, // 存疑提示也一并验证
      ),
    );
    await pumpPage(tester, customRemote: customRemote);
    await pickPhotoAndRecognize(tester);

    // 库未收录对话框：主行动「以估算值添加」可见（估值非空才展示）。
    expect(find.text('识别为「薯片」'), findsOneWidget);
    expect(find.text('以估算值添加'), findsOneWidget);

    await tester.tap(find.text('以估算值添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 表单预填：菜名 + 别名（英文通用名）+ 四营养 + 端侧徽标 + 存疑提示。
    expect(find.text('添加自定义食物'), findsOneWidget);
    expect(find.text('端侧估算，请确认'), findsOneWidget);
    expect(find.text('估算存疑，请核对数值'), findsOneWidget);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[0].controller!.text, '薯片'); // 菜名
    expect(fields[1].controller!.text, 'potato chips'); // 别名（英文名）
    expect(fields[2].controller!.text, '536'); // 热量
    expect(fields[3].controller!.text, '7'); // 蛋白质
    expect(fields[4].controller!.text, '53'); // 碳水
    expect(fields[5].controller!.text, '32'); // 脂肪

    // 保存 → 入本地库（远端 fake 成功）→ 结果卡回填。
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('确认记录'), findsOneWidget);
    // 已入本地库可搜（自定义食物）。
    final saved = await db.foodDao.searchFoods('薯片');
    expect(saved, hasLength(1));
    expect(saved.single.isCustom, isTrue);
    expect(saved.single.kcalPer100g, 536);

    // 份量必填：填入后确认入账（切离线确认：只落 pending，
    // 不启动 10s 上行计时器，测试假时钟不受扰）。
    recordRemote.mode = FakeRemoteMode.offline;
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    expect(entries, hasLength(1));
    expect(entries.single.foodId, saved.single.id);
    expect(entries.single.amountG, 150);
    await settleUi(tester);
  });
}

/// 可控推理网关：load / inferWithImage 挂起在完成器上，测试手动推进。
final class _ControllableGateway implements OnDeviceLlmGateway {
  bool _loaded = false;
  bool _vision = false;
  bool loadCalled = false;
  bool inferCalled = false;
  Completer<void>? _loadCompleter;
  Completer<String>? _inferCompleter;

  @override
  bool get isLoaded => _loaded;

  @override
  bool get visionEnabled => _loaded && _vision;

  @override
  Future<void> load(String modelPath, {bool enableVision = false}) {
    loadCalled = true;
    final completer = Completer<void>();
    _loadCompleter = completer;
    return completer.future.then((_) {
      _loaded = true;
      _vision = enableVision;
    });
  }

  void completeLoad() => _loadCompleter!.complete();

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
  }) {
    inferCalled = true;
    final completer = Completer<String>();
    _inferCompleter = completer;
    return completer.future;
  }

  void completeInfer(String response) => _inferCompleter!.complete(response);

  @override
  Future<void> unload() async {
    _loaded = false;
    _vision = false;
  }
}
