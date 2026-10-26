import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _nutrition = NutritionSnapshot(kcal: 60, proteinG: 5, carbG: 8, fatG: 1);

CustomFoodDraft _draft(CustomFoodSource source) => CustomFoodDraft(
  nameZh: '燕窝羹',
  aliasesZh: const ['燕窝'],
  per100g: _nutrition,
  source: source,
);

class _CapturingRemote implements CustomFoodRemote {
  final delegate = FakeCustomFoodRemote();
  final creates = <CustomFoodDraft>[];
  final updates = <CustomFoodDraft>[];

  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    final result = await delegate.createCustom(
      draft,
      clientRequestId: clientRequestId,
    );
    creates.add(draft);
    return result;
  }

  @override
  Future<void> updateCustom(String foodId, CustomFoodDraft draft) async {
    await delegate.updateCustom(foodId, draft);
    updates.add(draft);
  }

  @override
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) => delegate.contribute(
    foodId,
    clientRequestId: clientRequestId,
    barcode: barcode,
    evidenceImageUrl: evidenceImageUrl,
  );

  @override
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  }) =>
      delegate.getContributions(status: status, page: page, pageSize: pageSize);

  @override
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) => delegate.submitCorrection(
    foodId,
    draft,
    clientRequestId: clientRequestId,
  );

  @override
  Future<int> deleteCustom(String foodId) => delegate.deleteCustom(foodId);
}

class _Estimator implements UserEstimateSource {
  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async =>
      const FoodEstimate(
        per100g: NutritionSnapshot(kcal: 200, proteinG: 10, carbG: 20, fatG: 5),
        confidence: 'high',
      );
}

void main() {
  late AppDatabase db;
  late _CapturingRemote remote;
  late CustomFoodRepository repository;

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
    db = AppDatabase.memory();
    remote = _CapturingRemote();
    repository = CustomFoodRepository(db: db, remote: remote, userId: 'u-1');
  });
  tearDown(() async => db.close());

  for (final original in CustomFoodSource.values) {
    final next = original == CustomFoodSource.manual
        ? CustomFoodSource.llmEstimate
        : CustomFoodSource.manual;
    test('在线编辑来源 ${original.name} → ${next.name}：本地与 PATCH 一致', () async {
      final saved = await repository.save(_draft(original));
      final updated = await repository.update(saved.food, _draft(next));
      expect(updated.source, customFoodSourceName(next));
      expect((await db.foodDao.getById(updated.id))!.source, updated.source);
      expect(remote.updates.single.source, next);
    });

    test('离线待创建编辑来源 ${original.name} → ${next.name}：重放保留新来源', () async {
      remote.delegate.mode = FakeCustomFoodMode.offline;
      final saved = await repository.save(_draft(original));
      final updated = await repository.update(saved.food, _draft(next));
      expect(updated.source, customFoodSourceName(next));
      expect(
        updated.customClientRequestId,
        isNot(saved.food.customClientRequestId),
      );
      expect(remote.updates, isEmpty);
      remote.delegate.mode = FakeCustomFoodMode.success;
      expect(await repository.retryPending(), 1);
      expect(remote.creates.single.source, next);
      expect(
        (await db.foodDao.getById('srv-food-1'))!.source,
        customFoodSourceName(next),
      );
    });
  }

  Future<void> pumpEdit(WidgetTester tester, Food food) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = InMemoryLlmConfigStore();
    await config.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customFoodRepositoryProvider.overrideWithValue(repository),
          llmConfigStoreProvider.overrideWithValue(config),
          userEstimateSourceProvider.overrideWithValue(_Estimator()),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => CustomFoodSheet(editTarget: food),
                  ),
                  child: const Text('edit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
  }

  Future<void> saveAndUnmount(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(CustomFoodSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  for (final change in ['none', 'name', 'alias']) {
    testWidgets('编辑 AI 食品仅改 $change 保留来源，不虚构原估算渠道', (tester) async {
      final saved = await repository.save(_draft(CustomFoodSource.llmEstimate));
      await pumpEdit(tester, saved.food);
      expect(find.text('AI 估算，请核对数值'), findsOneWidget);
      expect(find.text('自定义 API 估算，请确认'), findsNothing);
      if (change != 'none') {
        await tester.enterText(
          find.byType(TextFormField).at(change == 'name' ? 0 : 1),
          '新名称',
        );
      }
      await saveAndUnmount(tester);
      expect(remote.updates.single.source, CustomFoodSource.llmEstimate);
      expect((await db.foodDao.getById(saved.food.id))!.source, 'llm-estimate');
    });
  }

  testWidgets('编辑 AI 食品手动改营养后来源改为个人填写', (tester) async {
    final saved = await repository.save(_draft(CustomFoodSource.llmEstimate));
    await pumpEdit(tester, saved.food);
    await tester.enterText(find.byType(TextFormField).at(2), '70');
    await saveAndUnmount(tester);
    expect(remote.updates.single.source, CustomFoodSource.manual);
    final updated = (await db.foodDao.getById(saved.food.id))!;
    expect(updated.source, 'manual');
    expect(updated.kcalPer100g, 70);
  });

  testWidgets('编辑手填食品重新 AI 估算后本地和上行均标为估算', (tester) async {
    final saved = await repository.save(_draft(CustomFoodSource.manual));
    await pumpEdit(tester, saved.food);
    await tester.tap(find.text('AI 估算'));
    await tester.pumpAndSettle();
    await saveAndUnmount(tester);
    expect(remote.updates.single.source, CustomFoodSource.llmEstimate);
    final updated = (await db.foodDao.getById(saved.food.id))!;
    expect(updated.source, 'llm-estimate');
    expect(updated.kcalPer100g, 200);
  });
}
