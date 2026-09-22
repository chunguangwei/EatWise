import 'package:drift/drift.dart' show Value;
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
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// 录制型假通道：收集上报批次（埋点断言用）。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> sent = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    sent.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

/// M3 记录页 widget 测试：主流程（搜索 → 选食物 → 份量实时重算 →
/// 确认乐观更新 → 「已记录·撤销」吐司 → 撤销撤回）+ 三入口占位 + 待同步角标。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late RecordRepository repository;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    repository = RecordRepository(
      db: db,
      remote: remote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    // 在 addTearDown（真实事件区）关闭资源；不要在测试体内 close——
    // drift 流退订时用 `Timer.run` 清理查询缓存，在 widget 测试的假时钟区
    // 里 await close 会等不到 Timer 触发而死锁（挂起 10 分钟超时）。
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾：隐藏吐司（取消其时长 Timer）→ 失焦输入框（取消光标
  /// 闪烁 Timer）→ 卸载页面并多次 pump。
  ///
  /// 卸载会退订 drift watch 流：退订回调经微任务完成后，drift 用
  /// `Timer.run` 延迟清理查询缓存（见 stream_queries.dart 注释），该 Timer
  /// 落在假时钟区，必须在其入队后再 pump 一次冲刷，否则 flutter_test 收尾
  /// 判定「Timer 未决」。db.close 留给 addTearDown（真实事件区），在测试体
  /// 内 await close 会等不到假时钟 Timer 触发而死锁挂起。
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          aiEngineAvailabilityFnProvider.overrideWithValue(
            () async => AiEngineAvailability.ondeviceReady,
          ),
          waterLogRepositoryProvider.overrideWithValue(
            WaterLogRepository(db: db),
          ),
          // 阶段 E 食物详情弹层的红绿灯徽标依赖每日营养目标
          // （生产由 main 注入 SharedPreferences 快照；测试注入兜底口径）。
          nutritionGoalProvider.overrideWithValue(
            const NutritionGoal(
              bmr: null,
              tdee: null,
              targetKcal: 2000,
              proteinG: 125,
              carbG: 225,
              fatG: 67,
              usedFallback: true,
              configVersion: '1.0.0',
            ),
          ),
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

  testWidgets('主流程：搜索 → 份量重算 → 确认入账 → 撤销撤回', (tester) async {
    await pumpPage(tester);

    // 初始：标题、三入口、无待同步角标。
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('拍照记'), findsOneWidget);
    expect(find.text('语音记'), findsOneWidget);
    expect(find.text('常吃'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsNothing);

    // 双语搜索（中文）。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('白米饭'), findsOneWidget);

    // 选中食物 → 阶段 E 食物详情弹层打开；份量留空必填（不再默认 100g 预览）。
    await tester.tap(find.text('白米饭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 弹层入场动画
    expect(find.text('确认记录'), findsOneWidget);
    expect(find.text('热量 116 千卡'), findsNothing);

    // 空份量点确认 → 拦截提示，不入账（弹层关闭，结果卡接管份量编辑）。
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入大于 0 的份量'), findsOneWidget);
    expect(await repository.entriesForDate(DateTime.now().toUtc()), isEmpty);

    // 份量修改 → 营养实时重算（US-3.1）。
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);

    // 确认 → 乐观更新：「已记录·撤销」吐司 + 待同步角标。
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsOneWidget);
    // v1.13.14 走查④：「待校准」历史标注已移除（本地聚合即权威口径）。
    expect(find.text('今日已记 1 笔 · 今日约 232 千卡'), findsOneWidget);
    expect(find.text('待校准'), findsNothing);

    // 撤销 → 记录撤回，角标消失（等吐司入场动画结束再点，否则命中失败）。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsNothing);
    expect(await repository.entriesForDate(DateTime.now().toUtc()), isEmpty);

    // 收尾：隐藏吐司 + 失焦输入框（不卸载页面，见 settleUi 注释）。
    await settleUi(tester);
  });

  testWidgets('拍照入口弹出取图来源选择（拍照/从相册选择）', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('搜索无结果 → 空态提示', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 空态三件套（薄荷走查 P2）：图标 + 引导文案 + 自定义食物 CTA。
    expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);
    expect(find.text('没找到？换个关键词试试'), findsOneWidget);
    expect(find.text('找不到？添加自定义食物'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('今日记录列表：搜索框为空且有记录时按餐次分组展示（无餐次归「其他」）', (tester) async {
    final today = localDateKey(DateTime.now());
    final nowIso = DateTime.now().toUtc().toIso8601String();
    Future<void> seedEntry(String id, String foodId, MealType? mealType) {
      return db.foodEntryDao.insertEntry(
        FoodEntriesCompanion(
          localId: Value(id),
          userId: const Value('anonymous'),
          clientRequestId: Value('req-$id'),
          syncStatus: const Value(SyncStatus.synced),
          datetimeUtc: Value(nowIso),
          localDate: Value(today),
          foodId: Value(foodId),
          amountG: const Value(100),
          kcal: const Value(116),
          proteinG: const Value(2.6),
          carbG: const Value(25.9),
          fatG: const Value(0.3),
          source: const Value(EntrySource.manual),
          mealType: Value(mealType),
          createdAtUtc: Value(nowIso),
          updatedAtUtc: Value(nowIso),
        ),
      );
    }

    await seedEntry('e1', 'f-rice', MealType.breakfast);
    await seedEntry('e2', 'f-egg', MealType.snack);
    await seedEntry('e3', 'f-chicken', null); // 历史无餐次 → 其他
    await pumpPage(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('今日记录'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('加餐'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('鸡胸肉'), findsOneWidget);
    // 午餐/晚餐组无记录 → 不渲染组标题。
    expect(find.text('午餐'), findsNothing);
    expect(find.text('晚餐'), findsNothing);

    // 输入搜索词 → 分组列表让位给搜索空态。
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('没找到？换个关键词试试'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('薄荷走查 P2：拍照记入口主色描边高亮，其余三格原样', (tester) async {
    await pumpPage(tester);

    final colors = AppTheme.light().extension<AppColors>()!;

    Container cardOf(String label) {
      final inkWell = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      return tester.widget<Container>(
        find.descendant(of: inkWell.first, matching: find.byType(Container)),
      );
    }

    // 拍照记：浅主色底 + 主色描边。
    final photoCard = cardOf('拍照记');
    final photoDecoration = photoCard.decoration! as BoxDecoration;
    expect(photoDecoration.border, isNotNull);
    expect((photoDecoration.border! as Border).top.color, colors.brandPrimary);

    // 其余三格：无描边。
    for (final label in <String>['语音记', '常吃', '扫码记']) {
      final decoration = cardOf(label).decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    }
    await settleUi(tester);
  });

  testWidgets('搜索框清空键：输入非空出现，点击清空并复位搜索词（走查 B-4）', (tester) async {
    await pumpPage(tester);

    // 初始无清空键。
    expect(find.byTooltip('清空搜索'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('清空搜索'), findsOneWidget);
    expect(find.text('白米饭'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('清空搜索'), findsNothing);
    final TextField searchField = tester.widget(find.byType(TextField).first);
    expect(searchField.controller!.text, isEmpty);

    await settleUi(tester);
  });

  testWidgets('键盘顶起：空态可滚不溢出，今日汇总行让位（走查 Y1）', (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPage(tester);

    // 记一笔让「今日已记」汇总行出现。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('白米饭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 详情弹层入场动画
    await tester.enterText(find.byType(TextField).last, '100');
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('今日已记 1 笔'), findsOneWidget);

    // 搜索无结果（先输入再抬键盘：先设 viewInsets 会让
    // enterText 的输入连接挂不上、静默丢输入）。
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 键盘顶起 600px（修复前：空态 + 汇总行 + 键盘 → BOTTOM OVERFLOWED 38px）。
    tester.view.viewInsets = FakeViewPadding(bottom: 600);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('没找到？换个关键词试试'), findsOneWidget);
    expect(find.textContaining('今日已记'), findsNothing); // 汇总行让位
    expect(tester.takeException(), isNull); // 无溢出异常

    tester.view.resetViewInsets();
    // 冲刷 10s 撤销窗上行 Timer（D-11），避免测试结束挂起 Timer。
    await tester.pump(const Duration(seconds: 11));
    await settleUi(tester);
  });
  testWidgets('连续入账：确认成功后重启记录流程，第二单埋点不丢', (tester) async {
    final client = _RecordingClient();
    final analytics = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[client],
    );
    await pumpPage(tester, analytics: analytics);

    // 第一单：搜索 → 详情弹层 → 份量 → 确认。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('白米饭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 详情弹层入场动画
    await tester.enterText(find.byType(TextField).last, '100');
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);

    // 第二单：同样链路再记一笔（修复前第二单起无任何流程埋点）。
    await tester.enterText(find.byType(TextField).first, '鸡蛋');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(ListTile, '鸡蛋'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 详情弹层入场动画
    await tester.enterText(find.byType(TextField).last, '50');
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await analytics.flush();

    // 进入页面 1 次 + 两单确认各重启 1 次 = 3 次 flow_start。
    final starts = client.sent
        .where((e) => e.name == 'record_flow_start')
        .toList();
    expect(starts, hasLength(3));
    // 两单各有 record_flow_success，且 flow_id 不同（一单一流程）。
    final successes = client.sent
        .where((e) => e.name == 'record_flow_success')
        .toList();
    expect(successes, hasLength(2));
    final firstFlowId = successes[0].properties['flow_id'];
    final secondFlowId = successes[1].properties['flow_id'];
    expect(secondFlowId, isNot(firstFlowId));
    // 两单的 flow_id 分别对应该单进行时的流程（首单=进入页开启，
    // 第二单=首单确认后重启；starts[2] 是第二单确认后再重启、页面退出时
    // 才 abandon 的流程）。
    expect(firstFlowId, starts[0].properties['flow_id']);
    expect(secondFlowId, starts[1].properties['flow_id']);
    // 步数按单重置：选中食物 + 确认 = 2 步（不累积上一单）。
    expect(successes[1].properties['step_count'], 2);

    // 冲刷 10s 撤销窗上行 Timer（D-11），避免测试结束挂起 Timer。
    await tester.pump(const Duration(seconds: 11));
    await settleUi(tester);
  });
}
