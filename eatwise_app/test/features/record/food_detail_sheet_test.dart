import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阶段 E 食物详情弹层 widget 测试：信息分层（名称/热量大字/供能三圆环/
/// 红绿灯徽标/明细折叠区）+ 份量输入实时预览 + 确认回调。
void main() {
  const food = Food(
    id: 'f-rice',
    nameZh: '白米饭',
    nameEn: 'White Rice',
    aliasesZh: '["米饭","白饭"]',
    aliasesEn: '["rice","steamed rice"]',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbPer100g: 25.9,
    fatPer100g: 0.3,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: 'req-1',
  );

  // 兜底口径目标（D-04 §1.6）：米饭四个 p 均远低于高侧边界 → 绿灯。
  const goal = NutritionGoal(
    bmr: null,
    tdee: null,
    targetKcal: 2000,
    proteinG: 125,
    carbG: 225,
    fatG: 67,
    usedFallback: true,
    configVersion: '1.0.0',
  );

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required ValueChanged<String> onConfirm,
    AppLocale locale = AppLocale.zhCn,
    Food food = food,
  }) async {
    await LocaleSettings.setLocale(locale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[nutritionGoalProvider.overrideWithValue(goal)],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: FoodDetailSheet(food: food, onConfirm: onConfirm),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // 自定义食物（个人库行）：详情弹层带编辑/分享/删除动作行。
  const customFood = Food(
    id: 'cf-1',
    nameZh: '自制燕窝羹',
    nameEn: 'Custom Bird Nest',
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 60,
    proteinPer100g: 5,
    carbPer100g: 8,
    fatPer100g: 1,
    isCustom: true,
    customSyncPending: false,
    customClientRequestId: 'req-cf',
  );

  testWidgets('信息分层：名称/绿灯徽标/热量大字/三圆环/人话注释/折叠区默认收起', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {});

    // 头部名称 + 红绿灯徽标（三重编码之一：文字）+ 判定依据注释。
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('绿灯 · 放心吃'), findsOneWidget);
    expect(find.text('按每 100 克对照你的每日营养目标判定'), findsOneWidget);

    // 显著热量卡：千卡/千焦并列 + 「大约需走 N 步」（每 100g 口径）。
    expect(find.text('116'), findsOneWidget);
    expect(find.text('千卡 / 485 千焦 · 每 100 克'), findsOneWidget);
    expect(find.text('大约需走 4292 步'), findsOneWidget);

    // 三圆环：供能占比（白米饭 蛋白质 9% / 碳水 89% / 脂肪 2%）+ 人话注释。
    expect(find.text('三大营养素供能比例'), findsOneWidget);
    expect(find.textContaining('2.25 倍'), findsOneWidget);
    expect(find.text('9%'), findsOneWidget);
    expect(find.text('89%'), findsOneWidget);
    expect(find.text('2%'), findsOneWidget);

    // 折叠区默认收起：明细行不可见。
    expect(find.text('每 100 克营养明细'), findsOneWidget);
    expect(find.textContaining('供能 10 千卡'), findsNothing);
  });

  testWidgets('折叠区展开：NRV% 表 + 三大营养素明细 + 别名', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {});
    await tester.ensureVisible(find.text('每 100 克营养明细'));
    await tester.pump();
    await tester.tap(find.text('每 100 克营养明细'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // NRV% 表：表头 + 能量行（kJ）+ 三大营养素行（无钠数据不出钠行）。
    expect(find.text('营养素'), findsOneWidget);
    expect(find.text('NRV%'), findsOneWidget);
    expect(find.text('485 千焦'), findsOneWidget); // 116 kcal × 4.184
    expect(find.text('6%'), findsOneWidget); // 能量 NRV
    expect(find.text('4%'), findsOneWidget); // 蛋白质 2.6/60
    expect(find.text('1%'), findsOneWidget); // 脂肪 0.3/60
    expect(find.text('钠'), findsNothing);

    expect(find.text('蛋白质 2.6 克 · 供能 10 千卡'), findsOneWidget);
    expect(find.text('碳水 25.9 克 · 供能 104 千卡'), findsOneWidget);
    expect(find.text('脂肪 0.3 克 · 供能 3 千卡'), findsOneWidget);
    expect(find.text('别名：米饭、白饭'), findsOneWidget);
  });

  testWidgets('份量输入实时预览 + 「大约需走 N 步」联动 + 确认回调带出份量', (tester) async {
    String? confirmed;
    await pumpSheet(tester, onConfirm: (text) => confirmed = text);

    // 初始无预览；步数按每 100g 口径。
    expect(find.text('热量 232 千卡'), findsNothing);
    expect(find.text('大约需走 4292 步'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);
    expect(find.text('蛋白质 5.2 克'), findsOneWidget);
    // 200g → 232 kcal × 37 ≈ 8584 步（随份量联动）。
    expect(find.text('大约需走 8584 步'), findsOneWidget);
    expect(find.text('大约需走 4292 步'), findsNothing);

    await tester.tap(find.text('确认记录'));
    await tester.pump();
    expect(confirmed, '200');
  });

  testWidgets('英文语言环境：名称/徽标/注释切英文', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {}, locale: AppLocale.en);
    expect(find.text('White Rice'), findsOneWidget);
    expect(find.text('Green · enjoy freely'), findsOneWidget);
    expect(find.textContaining('2.25×'), findsOneWidget);
    expect(find.text('Nutrition per 100 g'), findsOneWidget);
  });

  testWidgets('自定义食物：动作行含编辑/分享/删除', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {}, food: customFood);
    expect(
      find.byKey(const ValueKey<String>('foodDetail.edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.share')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.delete')),
      findsOneWidget,
    );
    expect(find.text('分享给所有用户'), findsOneWidget);
  });

  testWidgets('共享/内置食物：不渲染动作行', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {}); // 默认 isCustom=false
    expect(find.byKey(const ValueKey<String>('foodDetail.edit')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('foodDetail.share')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.delete')),
      findsNothing,
    );
  });

  testWidgets('自定义食物审核中：隐藏分享入口（徽标已示审核中）', (tester) async {
    await pumpSheet(
      tester,
      onConfirm: (_) {},
      food: customFood.copyWith(contributionStatus: const Value('pending')),
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.share')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.delete')),
      findsOneWidget,
    );
    expect(find.text('审核中'), findsOneWidget);
  });

  testWidgets('自定义食物已晋升共享（approved）：动作行全隐藏（改删权已失）', (tester) async {
    await pumpSheet(
      tester,
      onConfirm: (_) {},
      food: customFood.copyWith(contributionStatus: const Value('approved')),
    );
    expect(find.byKey(const ValueKey<String>('foodDetail.edit')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('foodDetail.share')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('foodDetail.delete')),
      findsNothing,
    );
  });
}
