import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_providers.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_label_ocr_service.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../social/social_test_fakes.dart';
import '../record_test_helper.dart';
import 'barcode_test_fakes.dart';

/// 录制型假通道：收集上报批次（埋点透传断言用）。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> sent = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    sent.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

/// 扫码未命中「补充商品信息」众包补录 widget 测试：
/// 入口可见 / 表单校验（缺照片、营养范围）/ 两步提交链路（barcode +
/// evidenceImageUrl 成对上行）/ 409 已上架分支 / 埋点透传。
void main() {
  const barcode = '7622210449283';

  late AppDatabase db;
  late RecordRepository repository;
  late FakeBarcodeScannerGateway scannerGateway;
  late FakeBarcodeFoodService barcodeService;
  late FakeCustomFoodRemote customRemote;
  late FakeUploadApi uploadApi;

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
    scannerGateway = FakeBarcodeScannerGateway();
    barcodeService = FakeBarcodeFoodService();
    customRemote = FakeCustomFoodRemote();
    uploadApi = FakeUploadApi();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾（同 barcode_flow_test：drift 流退订 Timer 需冲刷）。
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
    AnalyticsService? analytics,
    OnDeviceNutritionLabelOcrService? ocrService,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          waterLogRepositoryProvider.overrideWithValue(
            WaterLogRepository(db: db),
          ),
          customFoodRemoteProvider.overrideWithValue(customRemote),
          barcodeScannerGatewayProvider.overrideWithValue(scannerGateway),
          barcodeFoodServiceProvider.overrideWithValue(barcodeService),
          photoPickerGatewayProvider.overrideWithValue(
            FakePhotoPicker(pngBytes),
          ),
          uploadApiProvider.overrideWithValue(uploadApi),
          if (analytics != null)
            analyticsServiceProvider.overrideWithValue(analytics),
          if (ocrService != null)
            nutritionLabelOcrServiceProvider.overrideWithValue(ocrService),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  AnalyticsService recordingAnalytics(_RecordingClient client) {
    return AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[client],
    );
  }

  /// 扫码未命中 → 打开「补充商品信息」表单。
  Future<void> openContributeSheet(WidgetTester tester) async {
    await tester.tap(find.text('扫码记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('补充商品信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 选图（来源选择 → 拍照）→ 等上传完成。
  Future<void> pickAndUploadPhoto(WidgetTester tester) async {
    await tester.tap(find.text('拍摄 / 选择照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 填表单（商品名 + 每 100g 四营养）。
  Future<void> fillForm(WidgetTester tester, {String kcal = '480'}) async {
    await tester.enterText(find.byType(TextFormField).at(0), '测试饼干');
    await tester.enterText(find.byType(TextFormField).at(1), kcal);
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.enterText(find.byType(TextFormField).at(3), '60');
    await tester.enterText(find.byType(TextFormField).at(4), '20');
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.text('提交补录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  ProviderContainer containerOf(WidgetTester tester) {
    return ProviderScope.containerOf(tester.element(find.byType(RecordPage)));
  }

  testWidgets('未命中卡主行动「补充商品信息」可见 → 表单打开（条码只读展示）', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('扫码记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 未命中卡：主行动 + 两个次行动均在。
    expect(find.text('补充商品信息'), findsOneWidget);
    expect(find.text('手动搜索'), findsOneWidget);
    expect(find.text('添加自定义食物'), findsOneWidget);

    await tester.tap(find.text('补充商品信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 表单打开：标题 + 条码只读 + 照片必填区 + 提交按钮。
    expect(find.text('补充商品信息'), findsOneWidget);
    expect(find.text('商品条码：$barcode'), findsOneWidget);
    expect(find.text('包装营养表照片（必填）'), findsOneWidget);
    expect(find.text('提交补录'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('表单校验：缺照片不可提交；营养范围与自定义食物同口径', (tester) async {
    await pumpPage(tester);
    await openContributeSheet(tester);
    await fillForm(tester);

    await tapSubmit(tester);

    // 缺照片：内联错误，且未发起任何远端调用。
    expect(find.text('请拍摄或选择包装上的营养表照片'), findsOneWidget);
    expect(customRemote.receivedRequestIds, isEmpty);
    expect(customRemote.receivedContributeIds, isEmpty);

    // 营养范围：热量 >900 提示（自定义食物同口径）。
    await tester.enterText(find.byType(TextFormField).at(1), '1000');
    await tapSubmit(tester);
    expect(find.text('热量需在 0–900 千卡之间'), findsOneWidget);
    expect(customRemote.receivedRequestIds, isEmpty);
    await settleUi(tester);
  });

  testWidgets('两步提交链路：创建自定义食物 → 贡献带 barcode + evidenceImageUrl', (
    tester,
  ) async {
    final client = _RecordingClient();
    final analytics = recordingAnalytics(client);
    await pumpPage(tester, analytics: analytics);
    await openContributeSheet(tester);
    await pickAndUploadPhoto(tester);
    expect(uploadApi.calls, 1);

    await fillForm(tester);
    await tapSubmit(tester);

    // ① 创建自定义食物（服务端 id srv-food-1）② 贡献带条码 + 佐证照片成对上行。
    expect(customRemote.receivedRequestIds, hasLength(1));
    expect(customRemote.receivedContributeIds, hasLength(1));
    expect(customRemote.receivedContributeBarcodes, <String>[
      'srv-food-1|$barcode|/v1/uploads/srv-1.png',
    ]);
    // 成功提示 + 本地食物预填结果卡（自己立即可记餐，EntrySource.barcode）。
    expect(find.text('已提交，审核通过后全用户都能扫到'), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(recordSelectedFoodProvider)?.id, 'srv-food-1');
    expect(container.read(recordEntrySourceProvider), EntrySource.barcode);
    expect(container.read(recordAmountTextProvider), '');

    // 埋点：submit → success。
    await analytics.flush();
    final events = client.sent
        .where((e) => e.name == 'record_barcode_contribute')
        .toList();
    expect(events.map((e) => e.properties['result']), <String>[
      'submit',
      'success',
    ]);
    await settleUi(tester);
  });

  testWidgets('上传失败：就地重试成功后可提交；缺 URL 时不可提交', (tester) async {
    uploadApi.error = networkException;
    await pumpPage(tester);
    await openContributeSheet(tester);
    await pickAndUploadPhoto(tester);

    // 上传失败：错误文案 + 重试入口；提交被照片必填拦截。
    expect(find.text('重新上传'), findsOneWidget);
    await fillForm(tester);
    await tapSubmit(tester);
    expect(customRemote.receivedRequestIds, isEmpty);

    // 就地重试成功 → 提交放行。
    uploadApi.error = null;
    await tester.tap(find.text('重新上传'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tapSubmit(tester);
    expect(customRemote.receivedContributeBarcodes, hasLength(1));
    await settleUi(tester);
  });

  testWidgets('409 已上架：提示已在库并直接预填记账', (tester) async {
    final client = _RecordingClient();
    final analytics = recordingAnalytics(client);
    customRemote.contributeConflict = true;
    await pumpPage(tester, analytics: analytics);
    await openContributeSheet(tester);
    await pickAndUploadPhoto(tester);
    await fillForm(tester);
    await tapSubmit(tester);

    expect(find.text('该商品已在库，已为你预填'), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(recordSelectedFoodProvider)?.id, 'srv-food-1');
    expect(container.read(recordEntrySourceProvider), EntrySource.barcode);

    await analytics.flush();
    final events = client.sent
        .where((e) => e.name == 'record_barcode_contribute')
        .toList();
    expect(events, hasLength(2));
    expect(events.last.properties['result'], 'fail');
    expect(events.last.properties['reason'], 'conflict');
    await settleUi(tester);
  });
  testWidgets('一图两用：选图即佐证上传 + 端侧读表预填四营养（AI 读表徽标）', (tester) async {
    final gateway = _FakeOcrGateway()
      ..imageResponse = '1540 kJ => 7.2 => 53.0 => 32.1';
    await pumpPage(
      tester,
      ocrService: OnDeviceNutritionLabelOcrService(
        gateway: gateway,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        normalizeImage: (bytes) async => bytes,
      ),
    );
    await openContributeSheet(tester);

    await pickAndUploadPhoto(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 读数预填（1540 kJ / 4.184 ≈ 368.1 kcal）+ 徽标；上传照旧进行。
    String field(int index) => tester
        .widget<TextFormField>(find.byType(TextFormField).at(index))
        .controller!
        .text;
    expect(field(1), '368.1'); // 热量（0 是商品名）
    expect(field(2), '7.2');
    expect(field(3), '53');
    expect(field(4), '32.1');
    expect(find.text('AI 读表，请核对'), findsOneWidget);
    expect(uploadApi.uploaded, hasLength(1)); // 佐证上传不受影响
    await settleUi(tester);
  });

  testWidgets('端侧不可用 → 照片退回纯佐证（无徽标、字段不预填、不误导）', (tester) async {
    await pumpPage(tester); // 不注入 OCR 服务
    await openContributeSheet(tester);

    await pickAndUploadPhoto(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 读表，请核对'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
    expect(uploadApi.uploaded, hasLength(1));
    await settleUi(tester);
  });

  testWidgets('读不出 → 照片仍是佐证，字段不写入（静默降级）', (tester) async {
    final gateway = _FakeOcrGateway()..imageResponse = '无法识别';
    await pumpPage(
      tester,
      ocrService: OnDeviceNutritionLabelOcrService(
        gateway: gateway,
        modelPath: () async => '/fake/gemma4-e2b.litertlm',
        normalizeImage: (bytes) async => bytes,
      ),
    );
    await openContributeSheet(tester);

    await pickAndUploadPhoto(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 读表，请核对'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
    expect(uploadApi.uploaded, hasLength(1));
    await settleUi(tester);
  });
}

/// OCR 网关 Fake（仅视觉推理）。
final class _FakeOcrGateway implements OnDeviceLlmGateway {
  bool loaded = false;
  bool vision = false;
  String imageResponse = '';

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
  Future<String> inferWithAudio(
    String prompt,
    Uint8List wavBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
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
    int seed = 42,
  }) async {
    return imageResponse;
  }

  @override
  Future<void> unload() async {
    loaded = false;
    vision = false;
  }
}
