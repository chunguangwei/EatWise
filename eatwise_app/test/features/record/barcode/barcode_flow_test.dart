import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/barcode/data/barcode_food_service.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_providers.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

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

/// 「扫码记」流程 widget 测试：
/// 命中预填结果卡 / 404 双动作承接 / 非法条码 / 权限降级卡 / 埋点透传。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakeBarcodeScannerGateway scannerGateway;
  late FakeBarcodeFoodService barcodeService;
  late FakeCustomFoodRemote customRemote;

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
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾（同 record_page_test：drift 流退订 Timer 需冲刷）。
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
  }) async {
    // 放大测试屏幕：自定义食物弹层较高，默认 800x600 下保存按钮不可点。
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
          if (analytics != null)
            analyticsServiceProvider.overrideWithValue(analytics),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 从记录页点「扫码记」并完成查询。
  Future<void> tapBarcodeEntry(WidgetTester tester) async {
    await tester.tap(find.text('扫码记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  ProviderContainer containerOf(WidgetTester tester) {
    return ProviderScope.containerOf(tester.element(find.byType(RecordPage)));
  }

  testWidgets('命中 → 预填记录结果卡（EntrySource.barcode，份量留空必填）', (tester) async {
    barcodeService.outcomes['7622210449283'] = BarcodeLookupHit(barcodeFood());
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(barcodeService.calls, <String>['7622210449283']);
    // 结果卡出现（食物名 + 确认按钮）。
    expect(find.text('奥利奥原味夹心饼干'), findsOneWidget);
    expect(find.text('确认记录'), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(recordSelectedFoodProvider)?.id, 'off_7622210449283');
    expect(container.read(recordEntrySourceProvider), EntrySource.barcode);
    // 份量必填留空（与手动搜索/自定义食物口径一致）。
    expect(container.read(recordAmountTextProvider), '');
    await settleUi(tester);
  });

  testWidgets('未收录 404 → 双动作卡；「手动搜索」关闭回到搜索', (tester) async {
    // fake 默认 BarcodeLookupNotFound。
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(find.text('未收录该商品'), findsOneWidget);
    expect(find.text('手动搜索'), findsOneWidget);
    expect(find.text('添加自定义食物'), findsOneWidget);

    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未收录该商品'), findsNothing);
    // 主链路不受影响：搜索仍可用。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('白米饭'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('未收录 404 →「添加自定义食物」弹层预填条码到别名〔假设〕', (tester) async {
    await pumpPage(tester);

    await tapBarcodeEntry(tester);
    await tester.tap(find.text('添加自定义食物'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 弹层打开，别名输入框（TextFormField 序号 1）预填条码号。
    expect(find.text('添加自定义食物'), findsOneWidget);
    final aliasField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(aliasField.controller!.text, '7622210449283');
    await settleUi(tester);
  });

  testWidgets('非法条码（<8 位）→ 内联提示，不发起查询', (tester) async {
    scannerGateway.code = '123';
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(barcodeService.calls, isEmpty);
    expect(find.text('条码格式不正确，应为 8–14 位数字'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('相机权限拒绝 → 降级说明卡（去开启/手动搜索），不阻断记录', (tester) async {
    scannerGateway.throwDenied = true;
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(find.text('相机未授权'), findsOneWidget);
    expect(find.text('扫不了码也能记，手动搜索或输码一样快'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);
    expect(find.text('手动搜索'), findsOneWidget);

    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('相机未授权'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('用户退出扫码页（取消）→ 静默返回，结果卡不出现', (tester) async {
    scannerGateway.code = null;
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(scannerGateway.calls, 1);
    expect(barcodeService.calls, isEmpty);
    expect(find.text('确认记录'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('查询不可用（网络错误）→ 提示文案，不误判未收录', (tester) async {
    barcodeService.outcomes['7622210449283'] = const BarcodeLookupUnavailable(
      '网络连接失败',
    );
    await pumpPage(tester);

    await tapBarcodeEntry(tester);

    expect(find.text('网络连接失败'), findsOneWidget);
    expect(find.text('未收录该商品'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('埋点透传：扫码确认入账 entry_type=barcode', (tester) async {
    final client = _RecordingClient();
    final analytics = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[client],
    );
    barcodeService.outcomes['7622210449283'] = BarcodeLookupHit(barcodeFood());
    // 远端命中会先把食物合入本地缓存（RemoteBarcodeFoodService），fake 手动补齐。
    await db.into(db.foods).insert(barcodeFood());
    await pumpPage(tester, analytics: analytics);

    await tapBarcodeEntry(tester);
    // 填份量并确认入账。
    await tester.enterText(find.byType(TextField).last, '50');
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await analytics.flush();

    final success = client.sent
        .where((e) => e.name == 'record_flow_success')
        .toList();
    expect(success, hasLength(1));
    expect(success.single.properties['entry_type'], 'barcode');
    // 入账记录的 EntrySource 透传为 barcode（落库 textEnum）。
    final entries = await db.select(db.foodEntries).get();
    expect(entries.single.source, EntrySource.barcode);
    // 冲刷 10s 撤销窗上行 Timer（D-11），避免测试结束挂起 Timer。
    await tester.pump(const Duration(seconds: 11));
    await settleUi(tester);
  });
}
