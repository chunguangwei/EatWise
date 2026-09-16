import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
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
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
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

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(FakeSpeechGateway()),
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
