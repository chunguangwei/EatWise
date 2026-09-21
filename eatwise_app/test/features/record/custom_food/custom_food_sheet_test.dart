import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';

/// 用户自配 API 窄抽象替身（可注入结果；ok=false 模拟直连失败 503）。
final class _FakeUserClient implements UserEstimateSource {
  bool ok = true;
  FoodEstimate result = const FoodEstimate(
    per100g: NutritionSnapshot(kcal: 200, proteinG: 10, carbG: 20, fatG: 5),
    confidence: 'high',
  );

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    if (!ok) {
      throw const BusinessApiException(
        httpStatus: 503,
        code: 'ESTIMATE_UNAVAILABLE',
        message: 'estimate unavailable',
      );
    }
    return result;
  }
}

/// K2 自定义食物弹层 + 记录页集成 widget 测试。
///
/// 覆盖：无结果 CTA 入口、表单校验（空名/越界/非正数）、AI 估算成功预填
/// +「自定义 API 估算，请确认」徽标（low 置信度额外提示）、503 降级手动填写、
/// 保存后立刻可搜（自定义标签）+ 结果卡回填、份量必填联动、离线本地保存。
void main() {
  late AppDatabase db;
  late FakeRecordRemote recordRemote;
  late FakeCustomFoodRemote customRemote;
  late RecordRepository repository;
  late InMemoryLlmConfigStore llmStore;
  late _FakeUserClient userClient;

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
    // 估算链路：已配置用户自配 API（两级路由的第二级），由 userClient 决定成败。
    llmStore = InMemoryLlmConfigStore();
    await llmStore.save(
      const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'),
    );
    userClient = _FakeUserClient();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾：隐藏吐司 → 失焦输入框 → 卸载页面并多次 pump
  /// （drift 流退订 Timer 需冲刷，见 record_page_test settleUi 注释）。
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
    // 放大测试屏幕：弹层内容高（标题 + 6 字段 + 2 按钮），
    // 默认 800x600 下保存按钮不可点。
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
          // 估算编排器依赖：已配置用户自配 API，成败由 userClient 注入。
          llmConfigStoreProvider.overrideWithValue(llmStore),
          userEstimateSourceProvider.overrideWithValue(userClient),
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
  Future<void> openSheet(WidgetTester tester, {String query = '不存在的食物'}) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('找不到？添加自定义食物'), findsOneWidget);
    await tester.tap(find.text('找不到？添加自定义食物'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加自定义食物'), findsOneWidget);
  }

  /// 弹层字段（0 菜名 / 1 别名 / 2 热量 / 3 蛋白 / 4 碳水 / 5 脂肪）。
  Future<void> enterSheetField(WidgetTester tester, int index, String text) {
    return tester.enterText(find.byType(TextFormField).at(index), text);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('空表单校验：菜名必填 + 四营养必填 >0', (tester) async {
    await pumpPage(tester);
    await openSheet(tester);
    // 搜索词已预填菜名（走查修：空态 CTA initialName）；清空验证必填。
    await enterSheetField(tester, 0, '');

    await tapSave(tester);

    expect(find.text('请输入菜名'), findsOneWidget);
    expect(find.text('请填写大于 0 的数值'), findsNWidgets(4));
    expect(find.text('添加自定义食物'), findsOneWidget); // 弹层未关闭
    expect(await db.foodDao.searchFoods('不存在的食物'), isEmpty);
    await settleUi(tester);
  });

  testWidgets('越界与非正数校验：热量 ≤900、宏量 ≤100、必须 >0', (tester) async {
    await pumpPage(tester);
    await openSheet(tester);
    await enterSheetField(tester, 0, '测试菜');
    await enterSheetField(tester, 2, '1000'); // 热量越界
    await enterSheetField(tester, 3, '200'); // 宏量越界
    await enterSheetField(tester, 4, '0'); // 非正数
    await enterSheetField(tester, 5, '10');

    await tapSave(tester);

    expect(find.text('热量需在 0–900 千卡之间'), findsOneWidget);
    expect(find.text('需在 0–100 克之间'), findsOneWidget);
    expect(find.text('请填写大于 0 的数值'), findsOneWidget);
    expect(await db.foodDao.searchFoods('测试菜'), isEmpty);
    await settleUi(tester);
  });

  testWidgets('AI 估算成功：预填四营养 + 估算徽标，low 置信度额外提示', (tester) async {
    userClient.result = const FoodEstimate(
      per100g: NutritionSnapshot(kcal: 200, proteinG: 10, carbG: 20, fatG: 5),
      confidence: 'low',
    );
    await pumpPage(tester);
    await openSheet(tester);
    await enterSheetField(tester, 0, '手工丸子');

    await tester.tap(find.text('AI 估算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      '200',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(5))
          .controller!
          .text,
      '5',
    );
    expect(find.text('自定义 API 估算，请确认'), findsOneWidget);
    expect(find.text('置信度较低，请仔细核对数值'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('估算不可用（两级都失败，503）：降级提示，手动填写不阻断', (tester) async {
    userClient.ok = false;
    await pumpPage(tester);
    await openSheet(tester);
    await enterSheetField(tester, 0, '手工丸子');

    await tester.tap(find.text('AI 估算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('估算暂不可用，请手动填写'), findsOneWidget);
    expect(find.text('自定义 API 估算，请确认'), findsNothing);

    // 手动填写后可正常保存（降级不阻断）。
    await enterSheetField(tester, 2, '180');
    await enterSheetField(tester, 3, '12');
    await enterSheetField(tester, 4, '15');
    await enterSheetField(tester, 5, '6');
    await tapSave(tester);

    expect(find.text('添加自定义食物'), findsNothing); // 弹层关闭
    expect(find.text('确认记录'), findsOneWidget); // 结果卡回填
    final saved = await db.foodDao.searchFoods('手工丸子');
    expect(saved, hasLength(1));
    expect(saved.single.isCustom, isTrue);
    expect(saved.single.customSyncPending, isFalse);
    await settleUi(tester);
  });

  testWidgets('保存后：结果卡回填 + 份量必填联动 + 保存后立刻可搜（自定义标签）', (tester) async {
    await pumpPage(tester);
    await openSheet(tester);
    await enterSheetField(tester, 0, '手工丸子');

    // 估算预填（默认 high 样例 200/10/20/5）→ 带估算徽标保存。
    await tester.tap(find.text('AI 估算'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('自定义 API 估算，请确认'), findsOneWidget);
    await tapSave(tester);

    // 弹层关闭 → 自动填入记录结果卡（份量留空必填）。
    expect(find.text('确认记录'), findsOneWidget);

    // 份量必填联动：空份量确认 → 拦截提示，不入账。
    // （保存成功 Toast「已保存 + 分享给所有用户」会遮住底部按钮，先关闭。）
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).hideCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入大于 0 的份量'), findsOneWidget);
    expect(await repository.entriesForDate(DateTime.now().toUtc()), isEmpty);

    // 填份量 → 营养实时重算 → 确认入账。
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.pump();
    expect(find.text('热量 300 千卡'), findsOneWidget);
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    expect(
      await repository.entriesForDate(DateTime.now().toUtc()),
      hasLength(1),
    );

    // 撤销撤回（同时取消 10s 上行去抖 Timer，避免收尾 Timer 未决，
    // 与 record_page_test 主流程同法）。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('已撤销'), findsOneWidget);
    expect(await repository.entriesForDate(DateTime.now().toUtc()), isEmpty);

    // 保存后立刻可搜，结果行带「自定义」标签。
    await tester.enterText(find.byType(TextField).first, '手工丸子');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('自定义'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('离线保存：仅落本地 pending + 提示，结果卡照常回填', (tester) async {
    customRemote.mode = FakeCustomFoodMode.offline;
    await pumpPage(tester);
    await openSheet(tester);
    await enterSheetField(tester, 0, '手工丸子');
    await enterSheetField(tester, 2, '180');
    await enterSheetField(tester, 3, '12');
    await enterSheetField(tester, 4, '15');
    await enterSheetField(tester, 5, '6');
    await tapSave(tester);

    expect(find.text('已保存到本机，联网后自动同步'), findsOneWidget);
    expect(find.text('确认记录'), findsOneWidget); // 离线也回填结果卡
    final saved = await db.foodDao.searchFoods('手工丸子');
    expect(saved, hasLength(1));
    expect(saved.single.customSyncPending, isTrue);
    expect(saved.single.customClientRequestId, isNotEmpty);
    await settleUi(tester);
  });
}
