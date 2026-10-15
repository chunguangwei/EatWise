import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/food_entry_edit_sheet.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// 今日记录编辑弹层回归：打开预填现值 → 改份量（实时热量预览）+ 改餐次 →
/// 保存落库（快照重算 / 餐次写入）、弹层关闭并提示；非法份量禁用保存。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late tz.Location location;

  setUpAll(() => initRecordTestTimeZones());

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    location = tz.getLocation('Asia/Shanghai');
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDown(() => db.close());

  Future<FoodEntry> addEntry(RecordRepository repository) {
    return repository.addEntry(
      RecordDraft(
        foodId: 'f-rice',
        amountG: 100,
        mealUtc: DateTime.utc(2026, 7, 28, 4), // 上海 12:00 → lunch 预判
        source: EntrySource.manual,
      ),
    );
  }

  Future<RecordRepository> pumpSheet(
    WidgetTester tester,
    FoodEntry entry,
  ) async {
    final repository = RecordRepository(
      db: db,
      remote: remote,
      location: location,
      undoWindow: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showFoodEntryEditSheet(context, entry),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('打开预填份量与餐次；保存后快照重算、餐次落库、弹层关闭并提示', (tester) async {
    final createRepo = RecordRepository(
      db: db,
      remote: remote,
      location: location,
      undoWindow: const Duration(milliseconds: 20),
    );
    final entry = await addEntry(createRepo);
    await createRepo.dispose();
    expect(entry.mealType, MealType.lunch);

    final repository = await pumpSheet(tester, entry);

    expect(find.text('编辑记录'), findsOneWidget);
    expect(find.text('白米饭'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);

    // 改份量 → 实时预览按新量重算（116×2=232）。
    await tester.enterText(find.byType(TextField), '200');
    await tester.pump();
    expect(find.text('232 千卡'), findsOneWidget);

    // 改餐次：加餐。
    await tester.tap(find.widgetWithText(ChoiceChip, '加餐'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('编辑记录'), findsNothing);
    expect(find.text('已更新记录'), findsOneWidget);

    final updated = await db.foodEntryDao.getByLocalId(entry.localId);
    expect(updated!.amountG, 200);
    expect(updated.kcal, closeTo(232, 0.01));
    expect(updated.mealType, MealType.snack);
    // 聚合随编辑重算（当日 kcal = 232）。
    final daily = await db.foodEntryDao.getDailyNutrition(
      'anonymous',
      '2026-07-28',
    );
    expect(daily!.kcal, closeTo(232, 0.01));

    // 弹层关闭后餐次 provider 复位，防残留污染下次入账。
    await repository.dispose();
  });

  testWidgets('非法份量 → helper 提示且保存禁用', (tester) async {
    final createRepo = RecordRepository(
      db: db,
      remote: remote,
      location: location,
      undoWindow: const Duration(milliseconds: 20),
    );
    final entry = await addEntry(createRepo);
    await createRepo.dispose();

    final repository = await pumpSheet(tester, entry);

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(find.text('请输入大于 0 的份量'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(button.onPressed, isNull);

    await repository.dispose();
  });
}
