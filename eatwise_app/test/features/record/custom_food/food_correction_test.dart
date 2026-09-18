import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
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

/// 「数据有误？」食物纠错入口（薄荷走查 P3）widget 测试：
/// 详情弹层入口 → 纠错弹层（预填当前名称/四营养，精简表单）→
/// 提交入众包审核池（kind=correction，Fake 远程端断言上行）。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late FakeCustomFoodRemote customRemote;
  late RecordRepository repository;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    recordRemote = FakeRecordRemote();
    customRemote = FakeCustomFoodRemote();
    repository = RecordRepository(
      db: db,
      remote: recordRemote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾（同 record_page_test settleUi：drift 流退订 Timer 需冲刷）。
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
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('贡献类型解析：correction → 纠错枚举（未知串仍回落 custom）', () {
    expect(
      foodContributionKindFrom('correction'),
      FoodContributionKind.correction,
    );
    expect(foodContributionKindFrom('barcode'), FoodContributionKind.barcode);
    expect(foodContributionKindFrom('bogus'), FoodContributionKind.custom);
    expect(foodContributionKindFrom(null), FoodContributionKind.custom);
  });

  testWidgets('纠错链路：详情弹层入口 → 预填精简表单 → 提交上行 correction', (tester) async {
    await pumpPage(tester);

    // 搜索 → 打开食物详情弹层。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('白米饭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('数据有误？告诉我们'), findsOneWidget);

    // 打开纠错弹层：标题/副文案 + 预填当前名称与四营养；精简表单
    //（无别名/AI 估算/共享勾选）。
    await tester.tap(find.text('数据有误？告诉我们'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('数据纠错'), findsOneWidget);
    expect(find.text('改动会提交审核，通过后全用户生效'), findsOneWidget);
    expect(find.text('AI 估算'), findsNothing);
    expect(find.text('分享给所有用户（审核通过后大家都能搜到）'), findsNothing);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5)); // 菜名 + 四营养（无别名）
    String fieldText(int index) =>
        tester.widget<TextFormField>(fields.at(index)).controller!.text;
    expect(fieldText(0), '白米饭');
    expect(fieldText(1), '116');
    expect(fieldText(2), '2.6');

    // 改热量后提交 → 上行 correction（幂等键随请求记录），Toast 已提交审核。
    await tester.enterText(fields.at(1), '130');
    await tester.tap(find.text('提交纠错'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已提交审核'), findsOneWidget);
    expect(customRemote.receivedCorrectionIds, hasLength(1));
    expect(customRemote.receivedCorrectionIds.single, startsWith('f-rice:'));

    await settleUi(tester);
  });
}
