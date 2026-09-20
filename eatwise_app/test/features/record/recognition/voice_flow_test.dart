import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 语音录入流程 widget 测试（D-16）：词典全量加载回归——
/// 食物库超过 500 条时，排在截断线之外的词条也必须能匹配
/// （修复前 searchFoods('', limit: 500) 让尾部词条永远匹配不到）。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakeSpeechGateway speechGateway;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    // 600 条填充食物 + 目标词条排在 500 截断线之外。
    await db.foodDao.upsertAll(<FoodsCompanion>[
      for (var i = 0; i < 600; i++)
        FoodsCompanion(
          id: Value('f-filler-$i'),
          nameZh: Value('填充食物$i'),
          nameEn: Value('Filler Food $i'),
          aliasesZh: const Value('[]'),
          aliasesEn: const Value('[]'),
          kcalPer100g: const Value(100),
          proteinPer100g: const Value(5),
          carbPer100g: const Value(10),
          fatPer100g: const Value(2),
        ),
      const FoodsCompanion(
        id: Value('f-birdnest'),
        nameZh: Value('燕窝羹'),
        nameEn: Value('Bird Nest Soup'),
        aliasesZh: Value('["燕窝"]'),
        aliasesEn: Value('[]'),
        kcalPer100g: Value(60),
        proteinPer100g: Value(5),
        carbPer100g: Value(8),
        fatPer100g: Value(1),
      ),
    ]);
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.getLocation('Asia/Shanghai'),
    );
    speechGateway = FakeSpeechGateway();
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

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          speechGatewayProvider.overrideWithValue(speechGateway),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('词典全量加载：第 601 条食物也能语音命中并进明细确认弹层', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    speechGateway.onText!('一碗燕窝羹');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 命中第 601 条（500 截断线之外）：进明细确认弹层（修复后口径）。
    expect(find.text('没听出是什么食物，换个说法或手动搜索'), findsNothing);
    expect(find.text('确认这餐明细'), findsOneWidget);
    expect(find.text('燕窝羹'), findsOneWidget);
    await settleUi(tester);
  });

  test('FoodDao.allFoods：全量返回，不做 limit 截断', () async {
    final foods = await db.foodDao.allFoods();
    expect(foods, hasLength(601));
    expect(foods.map((f) => f.id), contains('f-birdnest'));
  });

  testWidgets('ASR 错误透传：识别不可用时给出可降级的提示', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    speechGateway.onError!('error_network');
    await tester.pump();

    expect(find.text('语音识别不可用，点右边键盘图标打字输入'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('良性错误分桶：没听清提示重说而非报错', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    speechGateway.onError!('error_no_match');
    await tester.pump();

    expect(find.text('没听清，请再说一次，或点右边键盘图标打字'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('静默失败兜底：6 秒无任何回传给出提示', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('没听清，请再说一次，或点右边键盘图标打字'), findsOneWidget);
    await settleUi(tester);
  });
}
