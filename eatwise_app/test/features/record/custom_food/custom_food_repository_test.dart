import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义食物仓储单测（K2：远端直调 + 本地落库 + 离线 pending 重试）。
///
/// 覆盖：在线保存落库可搜、离线仅落本地 pending、联网 retryPending
/// 幂等重试、业务错误上抛不落库。
void main() {
  late AppDatabase db;
  late FakeCustomFoodRemote remote;
  late CustomFoodRepository repository;

  const draft = CustomFoodDraft(
    nameZh: '燕窝羹',
    aliasesZh: <String>['燕窝'],
    per100g: NutritionSnapshot(kcal: 60, proteinG: 5, carbG: 8, fatG: 1),
    source: CustomFoodSource.manual,
  );

  setUp(() {
    db = AppDatabase.memory();
    remote = FakeCustomFoodRemote();
    repository = CustomFoodRepository(db: db, remote: remote);
  });

  tearDown(() async {
    await db.close();
  });

  test('在线保存：远端成功 + 本地落库 isCustom，立即可搜可记', () async {
    final result = await repository.save(draft);

    expect(result.uploaded, isTrue);
    expect(result.food.id, 'srv-food-1'); // 以服务端 ID 为本地主键
    expect(result.food.isCustom, isTrue);
    expect(result.food.customSyncPending, isFalse);
    expect(remote.receivedRequestIds, hasLength(1));

    // 保存后立即可搜（名称 + 别名 LIKE 命中）。
    final byName = await db.foodDao.searchFoods('燕窝羹');
    expect(byName.map((f) => f.id), contains('srv-food-1'));
    final byAlias = await db.foodDao.searchFoods('燕窝');
    expect(byAlias.map((f) => f.id), contains('srv-food-1'));
  });

  test('离线保存：仅落本地 pending，记录幂等键待重试', () async {
    remote.mode = FakeCustomFoodMode.offline;

    final result = await repository.save(draft);

    expect(result.uploaded, isFalse);
    expect(result.food.isCustom, isTrue);
    expect(result.food.customSyncPending, isTrue);
    expect(result.food.customClientRequestId, isNotEmpty);
    expect(remote.receivedRequestIds, isEmpty); // 未到达远端

    // 本地仍可搜（离线期间照常可记）。
    final hits = await db.foodDao.searchFoods('燕窝羹');
    expect(hits, hasLength(1));
  });

  test('联网后 retryPending：原幂等键上行成功，本地行重映射为服务端 id', () async {
    remote.mode = FakeCustomFoodMode.offline;
    final saved = await repository.save(draft);
    final pendingId = saved.food.customClientRequestId;
    final localId = saved.food.id;

    // 恢复在线 → 重试上行。
    remote.mode = FakeCustomFoodMode.success;
    final synced = await repository.retryPending();

    expect(synced, 1);
    expect(remote.receivedRequestIds, <String>[pendingId]); // 幂等键复用
    // 本地临时 id（custom-*）已重映射为服务端 id，pending 与幂等键清除。
    expect(await db.foodDao.getById(localId), isNull);
    final row = await db.foodDao.getById('srv-food-1');
    expect(row!.customSyncPending, isFalse);
    expect(row.customClientRequestId, isEmpty);

    // 重复 retryPending 不再上行（已无 pending）。
    expect(await repository.retryPending(), 0);
    expect(remote.receivedRequestIds, hasLength(1));
  });

  test('retryPending 级联改写引用该食物的饮食记录 foodId', () async {
    remote.mode = FakeCustomFoodMode.offline;
    final saved = await repository.save(draft);
    final localId = saved.food.id;
    // 离线期间用临时 id 记账（pending 待上行）。
    await db.foodEntryDao.insertEntry(
      FoodEntriesCompanion(
        localId: const Value('l-entry-1'),
        userId: const Value('u-1'),
        clientRequestId: const Value('c-entry-1'),
        syncStatus: const Value(SyncStatus.pending),
        datetimeUtc: const Value('2026-09-14T01:10:00.000Z'),
        localDate: const Value('2026-09-14'),
        foodId: Value(localId),
        amountG: const Value(200),
        kcal: const Value(120),
        proteinG: const Value(10),
        carbG: const Value(16),
        fatG: const Value(2),
        source: const Value(EntrySource.manual),
        createdAtUtc: const Value('2026-09-14T01:10:00.000Z'),
        updatedAtUtc: const Value('2026-09-14T01:10:00.000Z'),
      ),
    );

    remote.mode = FakeCustomFoodMode.success;
    expect(await repository.retryPending(), 1);

    // 记录引用已级联改写为服务端 id——上行时服务端 snapshotOf 才能
    // 按 foodId 查到食物（修复前永远卡 pending 的根因）。
    final entry = await db.foodEntryDao.getByLocalId('l-entry-1');
    expect(entry!.foodId, 'srv-food-1');
  });

  test('业务错误（4xx 校验拒绝）：上抛且不落库', () async {
    remote.mode = FakeCustomFoodMode.success;
    final rejecting = _RejectingRemote();
    final rejectingRepo = CustomFoodRepository(db: db, remote: rejecting);

    await expectLater(
      rejectingRepo.save(draft),
      throwsA(isA<BusinessApiException>()),
    );
    expect(await db.foodDao.searchFoods('燕窝羹'), isEmpty);
  });

  test('贡献成功：返回候选状态并落本地 contributionStatus', () async {
    final saved = await repository.save(draft);

    final status = await repository.contribute(saved.food.id);

    expect(status, 'pending');
    expect(remote.receivedContributeIds, hasLength(1));
    expect(
      remote.receivedContributeIds.single,
      startsWith('${saved.food.id}:'),
    );
    final row = (await db.foodDao.getById(saved.food.id))!;
    expect(row.contributionStatus, 'pending');

    // 审核通过（下行 approved）同样落库。
    remote.contributeStatus = 'approved';
    expect(await repository.contribute(saved.food.id), 'approved');
    expect(
      (await db.foodDao.getById(saved.food.id))!.contributionStatus,
      'approved',
    );
  });

  test('贡献幂等：同一 clientRequestId 重放返回首次状态，不重复入池', () async {
    // 仓储每次生成新幂等键；幂等语义在远程端（服务端幂等表替身）验证。
    await remote.contribute('srv-food-1', clientRequestId: 'req-c1');
    remote.contributeStatus = 'approved';
    final replay = await remote.contribute(
      'srv-food-1',
      clientRequestId: 'req-c1',
    );

    expect(replay, 'pending'); // 首次结果
    expect(remote.receivedContributeIds, hasLength(1));
  });

  test('贡献拒收（400 FOOD_CONTRIBUTE_REJECTED）：落 rejected 并上抛双语原因', () async {
    final saved = await repository.save(draft);
    remote.contributeRejected = true;

    await expectLater(
      repository.contribute(saved.food.id),
      throwsA(
        isA<BusinessApiException>()
            .having((e) => e.code, 'code', 'FOOD_CONTRIBUTE_REJECTED')
            .having((e) => e.httpStatus, 'httpStatus', 400)
            .having((e) => e.message, 'message', contains('未通过审核')),
      ),
    );
    expect(
      (await db.foodDao.getById(saved.food.id))!.contributionStatus,
      'rejected',
    );
  });

  test('离线贡献：网络错误上抛，本地状态保持不变', () async {
    final saved = await repository.save(draft);
    remote.mode = FakeCustomFoodMode.offline;

    await expectLater(
      repository.contribute(saved.food.id),
      throwsA(isA<NetworkApiException>()),
    );
    expect(
      (await db.foodDao.getById(saved.food.id))!.contributionStatus,
      isNull,
    );
  });
}

/// 模拟 422 校验拒绝的远程端（T7 口径：不可重试错误上抛）。
final class _RejectingRemote implements CustomFoodRemote {
  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) {
    throw const BusinessApiException(
      httpStatus: 422,
      code: 'VALIDATION_FAILED',
      message: '字段校验失败',
    );
  }

  @override
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) {
    throw UnimplementedError();
  }
}
