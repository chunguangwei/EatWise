import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/moderation/application/moderation_controller.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:eatwise/features/moderation/presentation/moderation_page.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 审批中心页 widget 测试：pending 列表渲染（名称/类型徽标/营养/条码/提交人/时间）、
/// 详情展开、通过/驳回（确认弹窗 + 原因）+ 操作反馈 snackbar、空态、错误重试。
void main() {
  late FakeModerationRemote remote;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    remote = FakeModerationRemote();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  ModerationCandidate candidate({
    required String id,
    String nameZh = '候选酱牛肉',
    FoodContributionKind kind = FoodContributionKind.custom,
    String? barcode,
    NutritionSnapshot? suggestionPer100g,
    String? suggestionNameZh,
  }) {
    return ModerationCandidate(
      id: id,
      foodId: 'cf-$id',
      submitterUserId: 'user-$id-submitter',
      kind: kind,
      createdAt: DateTime.utc(2026, 9, 10, 2, 30),
      nameZh: nameZh,
      barcode: barcode,
      per100g: const NutritionSnapshot(
        kcal: 200,
        proteinG: 8,
        carbG: 30,
        fatG: 5,
      ),
      suggestionPer100g: suggestionPer100g,
      suggestionNameZh: suggestionNameZh,
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          moderationRemoteProvider.overrideWithValue(remote),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ModerationPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pending 列表渲染：名称/类型徽标/营养摘要/条码/提交人/时间', (tester) async {
    remote.pending = <ModerationCandidate>[
      candidate(id: 'c-1'),
      candidate(
        id: 'c-2',
        nameZh: '条码可乐',
        kind: FoodContributionKind.barcode,
        barcode: '6901234567890',
      ),
    ];
    await pumpPage(tester);

    expect(find.text('审批中心'), findsOneWidget);
    expect(find.text('候选酱牛肉'), findsOneWidget);
    expect(find.text('条码可乐'), findsOneWidget);
    expect(find.text('自定义食品'), findsOneWidget);
    expect(find.text('条码商品'), findsOneWidget);
    expect(find.textContaining('200 千卡'), findsNWidgets(2));
    expect(find.text('条码：6901234567890'), findsOneWidget);
    expect(find.textContaining('user-c-1'), findsOneWidget); // 提交人截断展示
  });

  testWidgets('空态：暂无待审批候选', (tester) async {
    await pumpPage(tester);
    expect(find.text('暂无待审批的食品候选'), findsOneWidget);
  });

  testWidgets('展开详情 → 通过（确认弹窗）→ 出队 + 反馈 snackbar', (tester) async {
    remote.pending = <ModerationCandidate>[candidate(id: 'c-1')];
    await pumpPage(tester);

    // 未展开时无审核按钮。
    expect(find.text('通过'), findsNothing);
    await tester.tap(find.text('候选酱牛肉'));
    await tester.pumpAndSettle();
    expect(find.text('通过'), findsOneWidget);
    expect(find.text('驳回'), findsOneWidget);

    await tester.tap(find.text('通过'));
    await tester.pumpAndSettle();
    expect(find.text('通过后该食品将进入共享食物库，所有用户都能搜到。确认通过？'), findsOneWidget);
    // 确认弹窗里的「通过」按钮（列表按钮与弹窗按钮同名，取最后一个）。
    await tester.tap(find.text('通过').last);
    await tester.pumpAndSettle();

    expect(remote.receivedReviews, <String>['c-1:approve:']);
    expect(find.text('已通过'), findsOneWidget); // snackbar
    expect(find.text('候选酱牛肉'), findsNothing); // 已出队
    expect(find.text('暂无待审批的食品候选'), findsOneWidget);
  });

  testWidgets('驳回（填原因）→ 出队 + 反馈；纠错候选展示建议值对照', (tester) async {
    remote.pending = <ModerationCandidate>[
      candidate(
        id: 'c-9',
        nameZh: '白米饭',
        kind: FoodContributionKind.correction,
        suggestionPer100g: const NutritionSnapshot(
          kcal: 130,
          proteinG: 2.7,
          carbG: 28,
          fatG: 0.3,
        ),
        suggestionNameZh: '白米饭（熟）',
      ),
    ];
    await pumpPage(tester);

    await tester.tap(find.text('白米饭'));
    await tester.pumpAndSettle();
    expect(find.text('数据纠错'), findsOneWidget);
    expect(find.text('建议值'), findsOneWidget);
    expect(find.text('白米饭（熟）'), findsOneWidget);
    expect(find.textContaining('130 千卡'), findsOneWidget);

    await tester.tap(find.text('驳回'));
    await tester.pumpAndSettle();
    expect(find.text('驳回该候选'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '营养数据存疑');
    await tester.tap(find.text('驳回').last);
    await tester.pumpAndSettle();

    expect(remote.receivedReviews, <String>['c-9:reject:营养数据存疑']);
    expect(find.text('已驳回'), findsOneWidget);
  });

  testWidgets('错误态：加载失败提示 + 重试恢复', (tester) async {
    remote.listError = const BusinessApiException(
      httpStatus: 500,
      code: 'INTERNAL_ERROR',
      message: 'boom',
    );
    await pumpPage(tester);
    expect(find.text('boom'), findsOneWidget);

    remote.listError = null;
    remote.pending = <ModerationCandidate>[candidate(id: 'c-1')];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('候选酱牛肉'), findsOneWidget);
  });
}
