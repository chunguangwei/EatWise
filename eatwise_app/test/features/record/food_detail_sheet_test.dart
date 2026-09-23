import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/moderation/application/moderation_controller.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/settings/data/user_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

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
    List<Override> extraOverrides = const <Override>[],
  }) async {
    await LocaleSettings.setLocale(locale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          nutritionGoalProvider.overrideWithValue(goal),
          // userMeProvider 默认回落 null（非管理员视角；失败重试 timer
          // 会在假时钟区挂 pending，见 settings_providers 注释）。
          userMeProvider.overrideWith((ref) => Future<UserMeView?>.value()),
          ...extraOverrides,
        ],
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

  testWidgets('占位食物行（名称==id）：标题回退「未知食物」+ id 小字可查', (tester) async {
    // v1.13.18 走查：详情页同样不能把原始 id 当名字（回查补名前的兜底）。
    const placeholder = Food(
      id: 'cf_223767c7',
      nameZh: 'cf_223767c7',
      nameEn: 'cf_223767c7',
      aliasesZh: '[]',
      aliasesEn: '[]',
      kcalPer100g: 250,
      proteinPer100g: 10,
      carbPer100g: 5,
      fatPer100g: 20,
      isCustom: false,
      customSyncPending: false,
      customClientRequestId: '',
    );
    await pumpSheet(tester, onConfirm: (_) {}, food: placeholder);

    expect(find.text('未知食物'), findsOneWidget);
    expect(find.text('cf_223767c7'), findsOneWidget); // id 小字保留可查
  });

  group('管理员删除（role==admin，DELETE /v1/moderation/foods/:id）', () {
    const adminMe = UserMeView(
      id: 'u-admin',
      username: 'boss',
      maskedPhone: '',
      role: 'admin',
    );

    late AppDatabase db;
    late RecordRepository repo;
    late FakeModerationRemote remote;
    late List<Override> adminOverrides;

    setUp(() async {
      db = AppDatabase.memory();
      repo = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
      );
      remote = FakeModerationRemote();
      adminOverrides = <Override>[
        recordRepositoryProvider.overrideWithValue(repo),
        moderationRemoteProvider.overrideWithValue(remote),
        userMeProvider.overrideWith((ref) => Future.value(adminMe)),
      ];
      addTearDown(() async {
        await repo.dispose();
        await db.close();
      });
    });

    /// 落共享食物行 + 一条本机引用记录（admin 直清断言用）。
    Future<void> seedFoodWithEntry() async {
      await db.foodDao.upsertAll(<FoodsCompanion>[food.toCompanion(true)]);
      await db.foodEntryDao.insertEntry(
        FoodEntriesCompanion(
          localId: const Value('l-1'),
          userId: const Value('anonymous'),
          clientRequestId: const Value('cr-1'),
          syncStatus: const Value(SyncStatus.synced),
          serverId: const Value('srv-1'),
          datetimeUtc: const Value('2026-09-23T01:00:00.000Z'),
          localDate: Value(
            DateTime.now().toLocal().toIso8601String().substring(0, 10),
          ),
          foodId: const Value('f-rice'),
          amountG: const Value(200),
          kcal: const Value(232),
          proteinG: const Value(5.2),
          carbG: const Value(51.8),
          fatG: const Value(0.6),
          source: const Value(EntrySource.manual),
          createdAtUtc: const Value('2026-09-23T01:00:00.000Z'),
          updatedAtUtc: const Value('2026-09-23T01:00:00.000Z'),
        ),
      );
    }

    testWidgets('admin 共享食物见「删除（管理员）」；确认弹窗明示级联；删除成功直清+提示条数', (tester) async {
      await seedFoodWithEntry();
      remote.deleteFoodResult = 3;
      await pumpSheet(
        tester,
        onConfirm: (_) {},
        extraOverrides: adminOverrides,
      );

      final entry = find.byKey(
        const ValueKey<String>('foodDetail.adminDelete'),
      );
      expect(entry, findsOneWidget);
      expect(find.text('删除（管理员）'), findsOneWidget);

      // 确认弹窗：明示级联后果；取消不调用。
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('删除该食品？'), findsOneWidget);
      expect(find.text('将删除该食品及所有用户的相关饮食记录，不可撤销。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(remote.receivedFoodDeletes, isEmpty);

      // 确认 → 远端删除 + 本机直清 + snackbar 带级联条数 + 弹层关闭。
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(remote.receivedFoodDeletes, <String>['f-rice']);
      expect(find.text('已删除，级联清理 3 条记录'), findsOneWidget);
      expect(find.text('删除该食品？'), findsNothing); // 详情弹层已关闭
      // 本机直清：食物行删除 + 引用记录删除 + 聚合重算归零。
      expect(await db.foodDao.getById('f-rice'), isNull);
      expect(
        await db.foodEntryDao.entriesForFood('anonymous', 'f-rice'),
        isEmpty,
      );

      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).hideCurrentSnackBar();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('admin 查看自定义 owner 食物：仍是 owner 动作行，不显示管理员删除（互斥）', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        onConfirm: (_) {},
        food: customFood,
        extraOverrides: adminOverrides,
      );
      expect(
        find.byKey(const ValueKey<String>('foodDetail.edit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('foodDetail.delete')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('foodDetail.adminDelete')),
        findsNothing,
      );
    });

    testWidgets('404 NOT_FOUND（服务端已删的幽灵行）：本地直清 + 友好提示，不当错误', (tester) async {
      await seedFoodWithEntry();
      remote.deleteFoodError = const BusinessApiException(
        httpStatus: 404,
        code: 'NOT_FOUND',
        message: '资源不存在',
      );
      await pumpSheet(
        tester,
        onConfirm: (_) {},
        extraOverrides: adminOverrides,
      );

      final entry = find.byKey(
        const ValueKey<String>('foodDetail.adminDelete'),
      );
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 不弹原始错误；友好文案 + 弹层关闭 + 本机照样直清。
      expect(find.text('资源不存在'), findsNothing);
      expect(find.text('该食品已不存在，已从本地移除'), findsOneWidget);
      expect(find.text('删除该食品？'), findsNothing);
      expect(await db.foodDao.getById('f-rice'), isNull);
      expect(
        await db.foodEntryDao.entriesForFood('anonymous', 'f-rice'),
        isEmpty,
      );

      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).hideCurrentSnackBar();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('409 FOOD_UNDER_REVIEW：提示等待审核，弹层不关闭，本机不清理', (tester) async {
      await seedFoodWithEntry();
      remote.deleteFoodError = const BusinessApiException(
        httpStatus: 409,
        code: 'FOOD_UNDER_REVIEW',
        message: 'under review',
      );
      await pumpSheet(
        tester,
        onConfirm: (_) {},
        extraOverrides: adminOverrides,
      );

      final entry = find.byKey(
        const ValueKey<String>('foodDetail.adminDelete'),
      );
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('该食物正在审核中，暂时无法删除，请先等待审核完成'), findsOneWidget);
      expect(find.text('删除（管理员）'), findsOneWidget); // 详情仍在
      expect(await db.foodDao.getById('f-rice'), isNotNull);
      expect(
        await db.foodEntryDao.entriesForFood('anonymous', 'f-rice'),
        hasLength(1),
      );

      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).hideCurrentSnackBar();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
