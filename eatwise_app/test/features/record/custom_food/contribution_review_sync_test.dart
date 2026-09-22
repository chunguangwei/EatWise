import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/custom_food/application/contribution_review.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';

/// 贡献审核状态同步（乐观入账的审批联动）：
/// pending→approved 条目转正去标记；pending→rejected 清除本地记录 +
/// 聚合重算 + 一次性驳回通知；首轮静默建基线；匿名跳过。
void main() {
  late AppDatabase db;
  late FakeCustomFoodRemote remote;
  late ContributionStatusStore store;
  late ContributionReviewSync sync;
  late RecordRepository repository;
  late FakeRecordRemote recordRemote;
  late tz.Location location;
  var tick = 0;

  const userId = 'u-review';

  FoodContribution contribution(
    String id,
    FoodContributionStatus status, {
    String foodId = 'cf-1',
    FoodContributionKind kind = FoodContributionKind.custom,
  }) {
    return FoodContribution(
      id: id,
      foodId: foodId,
      status: status,
      kind: kind,
      reason: status == FoodContributionStatus.rejected ? '营养数据存疑' : null,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 19),
    );
  }

  /// 落一条引用 cf-1 的今日记录（离线 pending，模拟乐观入账未上行）。
  Future<void> addEntry({String foodId = 'cf-1'}) {
    return repository.addEntry(
      RecordDraft(
        foodId: foodId,
        amountG: 200,
        mealUtc: DateTime.now().toUtc(),
        source: EntrySource.manual,
      ),
    );
  }

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    location = tz.getLocation('Asia/Shanghai');
    // 审核中的自定义食物（乐观入账来源）。
    await db.foodDao.upsertAll(<FoodsCompanion>[
      const FoodsCompanion(
        id: Value('cf-1'),
        nameZh: Value('私房臊子面'),
        nameEn: Value('Private Noodles'),
        kcalPer100g: Value(200),
        proteinPer100g: Value(8),
        carbPer100g: Value(30),
        fatPer100g: Value(5),
        isCustom: Value(true),
        contributionStatus: Value('pending'),
      ),
    ]);
    remote = FakeCustomFoodRemote();
    store = ContributionStatusStore.inMemory(userId: userId);
    tick = 0;
    sync = ContributionReviewSync(
      db: db,
      remote: remote,
      store: store,
      userId: userId,
      onNoticesAdded: () => tick++,
    );
    recordRemote = FakeRecordRemote(mode: FakeRemoteMode.offline);
    repository = RecordRepository(
      db: db,
      remote: recordRemote,
      location: location,
      userId: userId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('首轮同步静默建基线：历史 rejected 不清理、不提示', () async {
    await addEntry();
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.rejected),
    ];

    final notices = await sync.syncNow();

    expect(notices, isEmpty);
    expect(tick, 0);
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), hasLength(1));
    expect(store.loadKnown(), <String, String>{'c-1': 'rejected'});
  });

  test('pending → rejected：本地记录清除 + 聚合重算 + 食物标记 rejected + 一次性通知', () async {
    await addEntry();
    await addEntry();
    // 首轮：pending 建基线（用户提交贡献后同步过一轮）。
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.pending),
    ];
    await sync.syncNow();
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), hasLength(2));

    // 审批驳回：次轮 diff 出迁移。
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.rejected),
    ];
    final notices = await sync.syncNow();

    expect(notices, <String>['私房臊子面']);
    expect(tick, 1);
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), isEmpty);
    final food = await db.foodDao.getById('cf-1');
    expect(food?.contributionStatus, 'rejected');
    // 聚合已重算为 0。
    final today = localDateKey(DateTime.now());
    final daily = await db.foodEntryDao.getDailyNutrition(userId, today);
    expect(daily?.entryCount, 0);
    expect(daily?.kcal, 0);
    // 通知入队待 UI drain；取走即清空（一次性）。custom 贡献驳回
    // correction=false（文案=「记录已移除」口径）。
    final queued = await store.drainNotices();
    expect(queued.map((final n) => (n.name, n.correction)).toList(), const [
      ('私房臊子面', false),
    ]);
    expect(await store.drainNotices(), isEmpty);
  });

  test('纠错驳回：记录保留不清理，通知 correction=true', () async {
    await addEntry();
    // 基线：纠错贡献 pending（对既有食物 cf-1 的数据纠错建议）。
    remote.contributions = <FoodContribution>[
      contribution(
        'k-1',
        FoodContributionStatus.pending,
        kind: FoodContributionKind.correction,
      ),
    ];
    await sync.syncNow();

    // 驳回：服务端 reject correction 不清贡献者记录（food.service 口径），
    // 客户端同样不得清理——通知只提示「建议未采纳」。
    remote.contributions = <FoodContribution>[
      contribution(
        'k-1',
        FoodContributionStatus.rejected,
        kind: FoodContributionKind.correction,
      ),
    ];
    final notices = await sync.syncNow();

    expect(notices, <String>['私房臊子面']);
    expect(tick, 1);
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), hasLength(1));
    final queued = await store.drainNotices();
    expect(queued.single.correction, isTrue);
  });

  test('驳回幂等：下一轮同状态不重复清理、不重复通知', () async {
    await addEntry();
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.pending),
    ];
    await sync.syncNow();
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.rejected),
    ];
    await sync.syncNow();

    final again = await sync.syncNow();
    expect(again, isEmpty);
    expect(tick, 1); // 只有一次
  });

  test('pending → approved：条目保留（快照不回溯），食物标记 approved 去「审核中」', () async {
    await addEntry();
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.pending),
    ];
    await sync.syncNow();

    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.approved),
    ];
    final notices = await sync.syncNow();

    expect(notices, isEmpty);
    expect(tick, 0);
    final entries = await db.foodEntryDao.entriesForFood(userId, 'cf-1');
    expect(entries, hasLength(1));
    expect(entries.single.kcal, 400); // 快照保留（200kcal/100g × 200g）
    final food = await db.foodDao.getById('cf-1');
    expect(food?.contributionStatus, 'approved');
  });

  test('存量校正：首轮服务端即 approved（无 pending 基线）→ 本地 pending 行去「审核中」，不提示', () async {
    await addEntry();
    // 用户提交贡献后一直没同步；期间管理员秒批。首轮直接见到 approved：
    // diff 无迁移（基线空），但本地行停在 pending 必须被校正。
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.approved),
    ];

    final notices = await sync.syncNow();

    expect(notices, isEmpty);
    expect(tick, 0);
    final food = await db.foodDao.getById('cf-1');
    expect(food?.contributionStatus, 'approved');
    // 记录保留（入账快照不回溯）。
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), hasLength(1));
  });

  test('存量校正同样覆盖 rejected：本地 pending 行校正为 rejected（不清记录不提示）', () async {
    await addEntry();
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.rejected),
    ];
    await sync.syncNow();

    final food = await db.foodDao.getById('cf-1');
    expect(food?.contributionStatus, 'rejected');
    // 首轮静默意图不变：记录保留、不通知（reject 级联由服务端软删 +
    // pull tombstone 收敛）。
    expect(await db.foodEntryDao.entriesForFood(userId, 'cf-1'), hasLength(1));
  });

  test('匿名用户跳过（贡献需登录，无候选可拉）', () async {
    final anonymous = ContributionReviewSync(
      db: db,
      remote: remote,
      store: ContributionStatusStore.inMemory(),
    );
    remote.contributions = <FoodContribution>[
      contribution('c-1', FoodContributionStatus.rejected),
    ];
    final notices = await anonymous.syncNow();
    expect(notices, isEmpty);
    expect(remote.receivedContributionQueries, isEmpty);
  });
}
