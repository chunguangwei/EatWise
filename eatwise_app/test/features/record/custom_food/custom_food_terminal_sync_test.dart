import 'package:drift/drift.dart' show Value;
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../fasting/tz_test_helper.dart';

/// 自定义食物上行终态收敛（v1.13.31）：永败阈值停重试、引用记录快照放行、
/// 失败徽标、手动重试复位。
void main() {
  setUpAll(() async {
    await initTestTimeZones();
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  CustomFoodRepository buildRepo(CustomFoodRemote remote) =>
      CustomFoodRepository(db: db, remote: remote);

  Future<Food> saveOfflineFood(CustomFoodRepository repo) async {
    final result = await repo.save(
      const CustomFoodDraft(
        nameZh: '永败臭豆腐',
        aliasesZh: <String>[],
        per100g: NutritionSnapshot(kcal: 100, proteinG: 5, carbG: 5, fatG: 5),
        source: CustomFoodSource.manual,
      ),
    );
    return result.food;
  }

  test('业务错误连续 5 次 → 终态失败停重试；网络错误不计数', () async {
    final remote = _ErroringCustomFoodRemote();
    final repo = buildRepo(remote);
    remote.mode = FakeCustomFoodMode.offline; // 先离线落 pending
    final food = await saveOfflineFood(repo);
    expect(food.customSyncPending, isTrue);

    // 网络错误（offline 抛 NetworkApiException）：整批 break，不计失败数。
    await repo.retryPending();
    var row = await db.foodDao.getById(food.id);
    expect(row!.customSyncFailCount, 0);
    expect(row.customSyncFailed, isFalse);

    // 业务错误 ×（阈值−1）：未终态；×阈值：终态停重试。
    remote.mode = FakeCustomFoodMode.success;
    remote.businessError = const BusinessApiException(
      httpStatus: 400,
      code: 'VALIDATION_ERROR',
      message: 'bad',
    );
    for (var i = 0; i < CustomFoodRepository.kTerminalFailThreshold - 1; i++) {
      await repo.retryPending();
    }
    row = await db.foodDao.getById(food.id);
    expect(
      row!.customSyncFailCount,
      CustomFoodRepository.kTerminalFailThreshold - 1,
    );
    expect(row.customSyncFailed, isFalse);

    await repo.retryPending();
    row = await db.foodDao.getById(food.id);
    expect(
      row!.customSyncFailCount,
      CustomFoodRepository.kTerminalFailThreshold,
    );
    expect(row.customSyncFailed, isTrue);

    // 终态后：retryPending 跳过不再打远端。
    final callsBefore = remote.createCalls;
    await repo.retryPending();
    expect(remote.createCalls, callsBefore);
  });

  test('终态失败食物的引用记录放行上行；未终态 pending 仍被守卫拦截', () async {
    final remote = FakeRecordRemote(mode: FakeRemoteMode.offline);
    final repo = RecordRepository(
      db: db,
      remote: remote,
      location: tz.getLocation('Asia/Shanghai'),
      userId: 'u1',
    );

    Future<FoodEntry> addFor(Food food) => repo.addEntry(
      RecordDraft(
        foodId: food.id,
        amountG: 100,
        mealUtc: DateTime.utc(2026, 9, 29, 4),
        source: EntrySource.manual,
      ),
    );

    // 未终态 pending：守卫拦截（保持 pending、远端零调用）。
    await db.foodDao.upsertAll(<FoodsCompanion>[
      _customFood('cf-pending', pending: true, failed: false),
      _customFood('cf-failed', pending: true, failed: true),
    ]);
    final blocked = await addFor((await db.foodDao.getById('cf-pending'))!);
    final released = await addFor((await db.foodDao.getById('cf-failed'))!);

    remote.mode = FakeRemoteMode.success;
    await repo.retryPending();

    final blockedRow = await db.foodEntryDao.getByLocalId(blocked.localId);
    expect(blockedRow!.syncStatus, SyncStatus.pending);
    final releasedRow = await db.foodEntryDao.getByLocalId(released.localId);
    expect(releasedRow!.syncStatus, SyncStatus.synced);
    expect(remote.pushCount, 1); // 只有放行那条上行
  });

  test('手动重试：复位失败态 → 上行成功清 pending（remap 服务端 id）', () async {
    final remote = _ErroringCustomFoodRemote();
    final repo = buildRepo(remote);
    remote.mode = FakeCustomFoodMode.offline;
    final food = await saveOfflineFood(repo);
    remote.mode = FakeCustomFoodMode.success;
    remote.businessError = const BusinessApiException(
      httpStatus: 400,
      code: 'VALIDATION_ERROR',
      message: 'bad',
    );
    for (var i = 0; i < CustomFoodRepository.kTerminalFailThreshold; i++) {
      await repo.retryPending();
    }
    expect((await db.foodDao.getById(food.id))!.customSyncFailed, isTrue);

    // 服务端恢复 → 手动重试：复位 → 上行成功（id remap）。
    remote.businessError = null;
    final ok = await repo.retryFailedNow(food.id);
    expect(ok, isTrue);
    expect(await db.foodDao.getById(food.id), isNull); // 已 remap 到服务端 id
    final remapped = await db.foodDao.getById('srv-food-1');
    expect(remapped, isNotNull);
    expect(remapped!.customSyncPending, isFalse);
    expect(remapped.customSyncFailed, isFalse);
  });

  test('失败徽标：终态失败优先于贡献状态显示「同步失败」', () async {
    final cs = CustomFoodStrings.testing(
      LocaleSettings.currentLocale.buildSync(),
    );
    await db.foodDao.upsertAll(<FoodsCompanion>[
      _customFood('cf-badge', pending: true, failed: true),
    ]);
    final food = (await db.foodDao.getById('cf-badge'))!;
    expect(cs.badgeFor(food), cs.badgeSyncFailed);

    final normal = (await db.foodDao.getById(
      'cf-badge',
    ))!.copyWith(customSyncFailed: false);
    expect(cs.badgeFor(normal), isNot(cs.badgeSyncFailed));
  });
}

FoodsCompanion _customFood(
  String id, {
  required bool pending,
  required bool failed,
}) {
  return FoodsCompanion(
    id: Value(id),
    nameZh: const Value('测试食物'),
    nameEn: const Value('Test food'),
    aliasesZh: const Value('[]'),
    aliasesEn: const Value('[]'),
    kcalPer100g: const Value(100),
    proteinPer100g: const Value(5),
    carbPer100g: const Value(5),
    fatPer100g: const Value(5),
    isCustom: const Value(true),
    customSyncPending: Value(pending),
    customClientRequestId: Value('req-$id'),
    customSyncFailCount: Value(failed ? 5 : 0),
    customSyncFailed: Value(failed),
  );
}

/// 可注入业务错误的自定义食物远端（其余行为委托 Fake——final class 不可
/// 继承，用 implements + 委托）。
final class _ErroringCustomFoodRemote implements CustomFoodRemote {
  _ErroringCustomFoodRemote([FakeCustomFoodRemote? delegate])
    : _delegate = delegate ?? FakeCustomFoodRemote();

  final FakeCustomFoodRemote _delegate;

  BusinessApiException? businessError;
  int createCalls = 0;

  FakeCustomFoodMode get mode => _delegate.mode;
  set mode(FakeCustomFoodMode value) => _delegate.mode = value;

  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    createCalls++;
    final e = businessError;
    if (e != null && mode != FakeCustomFoodMode.offline) throw e;
    return _delegate.createCustom(draft, clientRequestId: clientRequestId);
  }

  @override
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) => _delegate.contribute(
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
  }) => _delegate.getContributions(
    status: status,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) => _delegate.submitCorrection(
    foodId,
    draft,
    clientRequestId: clientRequestId,
  );

  @override
  Future<void> updateCustom(String foodId, CustomFoodDraft draft) =>
      _delegate.updateCustom(foodId, draft);

  @override
  Future<int> deleteCustom(String foodId) => _delegate.deleteCustom(foodId);
}
