import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
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

/// K2 众包贡献 widget 测试：勾选贡献成功流、机审拒收双语提示、
/// 事后贡献入口、搜索结果行四种状态标签 + 社区标签渲染。
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

  /// 测试收尾（与 custom_food_sheet_test settleUi 同法）。
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
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 打开自定义食物弹层（搜索无结果 → CTA）。
  Future<void> openSheet(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '手工丸子');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('找不到？添加自定义食物'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加自定义食物'), findsOneWidget);
  }

  /// 填写弹层（菜名 + 四营养；字段序 0 菜名 / 2 热量 / 3 蛋白 / 4 碳水 / 5 脂肪）。
  Future<void> fillSheet(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), '手工丸子');
    await tester.enterText(find.byType(TextFormField).at(2), '200');
    await tester.enterText(find.byType(TextFormField).at(3), '10');
    await tester.enterText(find.byType(TextFormField).at(4), '20');
    await tester.enterText(find.byType(TextFormField).at(5), '5');
  }

  /// 勾选/确认「分享给所有用户」开关默认不勾。
  Future<void> tapShareOptIn(WidgetTester tester) async {
    await tester.tap(find.text('分享给所有用户（审核通过后大家都能搜到）'));
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 搜索并等待结果列表刷新。
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('贡献开关默认不勾；勾选保存 → 调 contribute → 「已提交审核」+ 状态落库', (tester) async {
    await pumpPage(tester);
    await openSheet(tester);

    // 默认不勾。
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await fillSheet(tester);
    await tapShareOptIn(tester);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tapSave(tester);

    // 弹层关闭 + 「已提交审核」反馈。
    expect(find.text('添加自定义食物'), findsNothing);
    expect(find.text('已提交审核'), findsOneWidget);

    // contribute 幂等上行一次，状态落本地（pending）。
    expect(customRemote.receivedContributeIds, hasLength(1));
    final saved = await db.foodDao.searchFoods('手工丸子');
    expect(saved, hasLength(1));
    expect(saved.single.contributionStatus, 'pending');

    // 搜索结果行显示「审核中」标签。
    await search(tester, '手工丸子');
    expect(find.text('审核中'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('勾选保存被拒收：显示服务端双语原因，状态落 rejected，标签「未通过」', (tester) async {
    customRemote.contributeRejected = true;
    await pumpPage(tester);
    await openSheet(tester);
    await fillSheet(tester);
    await tapShareOptIn(tester);
    await tapSave(tester);

    // 保存本身成功（弹层关闭），拒收原因上屏（服务端 message）。
    expect(find.text('添加自定义食物'), findsNothing);
    expect(find.text('食物名称未通过审核，无法贡献到共享食物库'), findsOneWidget);
    expect(find.text('已提交审核'), findsNothing);

    final saved = await db.foodDao.searchFoods('手工丸子');
    expect(saved.single.contributionStatus, 'rejected');

    await search(tester, '手工丸子');
    expect(find.text('未通过'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('未勾选保存：Toast 提供「分享给所有用户」二次动作，事后贡献成功', (tester) async {
    await pumpPage(tester);
    await openSheet(tester);
    await fillSheet(tester);
    await tapSave(tester);

    // 保存成功 Toast + 二次动作入口（保存时未贡献）。
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('分享给所有用户'), findsOneWidget);
    expect(customRemote.receivedContributeIds, isEmpty);

    // 点二次动作 → 事后贡献 → 「已提交审核」。
    await tester.tap(find.text('分享给所有用户'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已提交审核'), findsOneWidget);
    expect(customRemote.receivedContributeIds, hasLength(1));
    final saved = await db.foodDao.searchFoods('手工丸子');
    expect(saved.single.contributionStatus, 'pending');

    // 状态标签立即可见。
    await search(tester, '手工丸子');
    expect(find.text('审核中'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('状态标签渲染：自定义/审核中/已共享/未通过/社区', (tester) async {
    FoodsCompanion food(String id, String name, {String? status}) =>
        FoodsCompanion(
          id: Value(id),
          nameZh: Value(name),
          nameEn: Value(name),
          aliasesZh: const Value('["标签测试"]'),
          kcalPer100g: const Value(100),
          proteinPer100g: const Value(10),
          carbPer100g: const Value(10),
          fatPer100g: const Value(5),
          isCustom: const Value(true),
          contributionStatus: status == null
              ? const Value.absent()
              : Value(status),
        );
    await db.foodDao.upsertAll(<FoodsCompanion>[
      food('c-none', '未贡献食物'),
      food('c-pending', '审核中食物', status: 'pending'),
      food('c-approved', '已共享食物', status: 'approved'),
      food('c-rejected', '未通过食物', status: 'rejected'),
      // 他人贡献的社区食物（非本人创建：isCustom=false + 下行标记 approved）。
      food(
        'c-community',
        '社区食物',
        status: 'approved',
      ).copyWith(isCustom: const Value(false)),
    ]);
    await pumpPage(tester);

    await search(tester, '标签测试');

    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('审核中'), findsOneWidget);
    expect(find.text('已共享'), findsOneWidget);
    expect(find.text('未通过'), findsOneWidget);
    expect(find.text('社区'), findsOneWidget);
    await settleUi(tester);
  });
}
