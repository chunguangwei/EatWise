import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/custom_food/presentation/my_contributions_page.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';

/// 我的贡献列表页 widget 测试：三重编码状态标签 + 拒绝原因 + 提交时间、
/// 食物名本地解析与回退、状态过滤查询口径、空态、错误重试。
void main() {
  late AppDatabase db;
  late FakeCustomFoodRemote customRemote;
  late RecordRepository repository;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    customRemote = FakeCustomFoodRemote();
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.getLocation('Asia/Shanghai'),
    );
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  FoodContribution contribution({
    required String id,
    required String foodId,
    required FoodContributionStatus status,
    String? reason,
    FoodContributionKind kind = FoodContributionKind.custom,
    String? barcode,
    String createdAt = '2026-09-01T02:30:00.000Z',
  }) {
    return FoodContribution(
      id: id,
      foodId: foodId,
      status: status,
      reason: reason,
      kind: kind,
      barcode: barcode,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(createdAt),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          customFoodRemoteProvider.overrideWithValue(customRemote),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MyContributionsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('列表渲染：食物名本地解析 + 三重编码状态标签 + 拒绝原因 + 提交时间', (tester) async {
    customRemote.contributions = <FoodContribution>[
      contribution(
        id: 'fc-1',
        foodId: 'f-rice',
        status: FoodContributionStatus.rejected,
        reason: '营养数据存疑',
      ),
      contribution(
        id: 'fc-2',
        foodId: 'f-egg',
        status: FoodContributionStatus.approved,
      ),
      contribution(
        id: 'fc-3',
        foodId: 'cf-missing',
        status: FoodContributionStatus.pending,
      ),
    ];
    await pumpPage(tester);

    // 食物名按 foodId 解析本地库；解析不到回退展示 foodId。
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('cf-missing'), findsOneWidget);

    // 状态三重编码：同一标签内 颜色 + 图标 + 文字（不单靠色相区分）。
    Future<void> expectBadge(IconData icon, String label, Color color) async {
      final badge = find
          .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
          .first;
      expect(
        find.descendant(of: badge, matching: find.text(label)),
        findsOneWidget,
      );
      final decoration =
          tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect(decoration.color, color.withValues(alpha: 0.12));
    }

    const palette = AppColors.light;
    await expectBadge(Icons.cancel_outlined, '已拒绝', palette.signalRed);
    await expectBadge(Icons.check_circle_outline, '已通过', palette.signalGreen);
    await expectBadge(
      Icons.hourglass_top_outlined,
      '审核中',
      palette.signalYellow,
    );
    // 拒绝原因只在该条目展示；提交时间为本地时区格式化。
    expect(find.text('拒绝原因：营养数据存疑'), findsOneWidget);
    expect(find.textContaining('提交于 2026-09-01 '), findsNWidgets(3));
  });

  testWidgets('状态过滤：切换 chips 按 status 查询并只渲染命中条目', (tester) async {
    customRemote.contributions = <FoodContribution>[
      contribution(
        id: 'fc-1',
        foodId: 'f-rice',
        status: FoodContributionStatus.rejected,
        reason: '图片不清晰',
      ),
      contribution(
        id: 'fc-2',
        foodId: 'f-egg',
        status: FoodContributionStatus.approved,
      ),
    ];
    await pumpPage(tester);
    expect(customRemote.receivedContributionQueries, contains('all/1/20'));

    await tester.tap(find.widgetWithText(ChoiceChip, '已拒绝'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(customRemote.receivedContributionQueries, contains('rejected/1/20'));
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('鸡蛋'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
  });

  testWidgets('条码补录条目：展示条码徽标 + 条码号', (tester) async {
    customRemote.contributions = <FoodContribution>[
      contribution(
        id: 'fc-b1',
        foodId: 'f-rice',
        status: FoodContributionStatus.pending,
        kind: FoodContributionKind.barcode,
        barcode: '7622210449283',
      ),
      contribution(
        id: 'fc-b2',
        foodId: 'f-egg',
        status: FoodContributionStatus.pending,
      ),
    ];
    await pumpPage(tester);

    // 条码贡献：类型徽标 + 条码号；普通贡献不展示徽标。
    expect(find.text('条码商品'), findsOneWidget);
    expect(find.text('条码 7622210449283'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
  });

  testWidgets('空态：无贡献记录显示占位文案', (tester) async {
    await pumpPage(tester);
    expect(find.text('暂无贡献记录'), findsOneWidget);
    expect(find.text('我的贡献'), findsOneWidget);
  });

  testWidgets('错误态：加载失败可重试恢复', (tester) async {
    customRemote.mode = FakeCustomFoodMode.offline;
    await pumpPage(tester);
    expect(find.text('加载失败，请稍后重试'), findsOneWidget);

    customRemote.mode = FakeCustomFoodMode.success;
    customRemote.contributions = <FoodContribution>[
      contribution(
        id: 'fc-1',
        foodId: 'f-rice',
        status: FoodContributionStatus.pending,
      ),
    ];
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('加载失败，请稍后重试'), findsNothing);
  });
}
