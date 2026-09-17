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

  testWidgets('信息分层：名称/绿灯徽标/热量大字/三圆环/人话注释/折叠区默认收起', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {});

    // 头部名称 + 红绿灯徽标（三重编码之一：文字）+ 判定依据注释。
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('绿灯 · 放心吃'), findsOneWidget);
    expect(find.text('按每 100 克对照你的每日营养目标判定'), findsOneWidget);

    // 显著热量卡。
    expect(find.text('116'), findsOneWidget);
    expect(find.text('千卡 / 每 100 克'), findsOneWidget);

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

  testWidgets('折叠区展开：三大营养素明细 + 别名', (tester) async {
    await pumpSheet(tester, onConfirm: (_) {});
    await tester.ensureVisible(find.text('每 100 克营养明细'));
    await tester.pump();
    await tester.tap(find.text('每 100 克营养明细'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('蛋白质 2.6 克 · 供能 10 千卡'), findsOneWidget);
    expect(find.text('碳水 25.9 克 · 供能 104 千卡'), findsOneWidget);
    expect(find.text('脂肪 0.3 克 · 供能 3 千卡'), findsOneWidget);
    expect(find.text('别名：米饭、白饭'), findsOneWidget);
  });

  testWidgets('份量输入实时预览 + 确认回调带出份量', (tester) async {
    String? confirmed;
    await pumpSheet(tester, onConfirm: (text) => confirmed = text);

    // 初始无预览。
    expect(find.text('热量 232 千卡'), findsNothing);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);
    expect(find.text('蛋白质 5.2 克'), findsOneWidget);

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
}
