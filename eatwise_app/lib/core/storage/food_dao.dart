import 'package:drift/drift.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'food_dao.g.dart';

/// Food 食物库 DAO（D-16：中英双语条目 + 别名搜索）。
@DriftAccessor(tables: <Type>[Foods])
class FoodDao extends DatabaseAccessor<AppDatabase> with _$FoodDaoMixin {
  FoodDao(super.db);

  Expression<bool> _visibleTo(Foods f, String userId) {
    final legacyAnonymous = userId == 'anonymous'
        ? (f.isCustom & f.ownerUserId.isNull())
        : const Constant(false);
    return f.isCustom.equals(false) |
        f.ownerUserId.equals(userId) |
        legacyAnonymous;
  }

  Expression<bool> _ownedCustom(Foods f, String userId) {
    return f.isCustom & f.ownerUserId.equals(userId);
  }

  /// 共享食物全局可见；个人食物只对 owner 可见。匿名兼容升级前
  /// owner=null 的历史行，首次登录认领后即从匿名命名空间移出。
  Future<List<Food>> searchFoods(
    String query, {
    int limit = 20,
    String ownerUserId = 'anonymous',
  }) {
    final keyword = query.trim();
    final statement = select(foods)
      ..where((f) => _visibleTo(f, ownerUserId))
      ..limit(limit);
    if (keyword.isNotEmpty) {
      final pattern = '%$keyword%';
      statement.where(
        (f) =>
            f.nameZh.like(pattern) |
            f.nameEn.like(pattern) |
            f.aliasesZh.like(pattern) |
            f.aliasesEn.like(pattern),
      );
    }
    return statement.get();
  }

  /// 按主键取食物；传 owner 时共享食物放行、他人个人食物排除。
  Future<Food?> getById(String id, {String? ownerUserId}) {
    final statement = select(foods)..where((f) => f.id.equals(id));
    if (ownerUserId != null) {
      statement.where((f) => _visibleTo(f, ownerUserId));
    }
    return statement.getSingleOrNull();
  }

  /// Resolve a temporary identity after deterministic downlink/create binding.
  Future<Food?> customFoodByIdentity(
    String id, {
    required String ownerUserId,
  }) async {
    final direct =
        await (select(foods)
              ..where((f) => _ownedCustom(f, ownerUserId) & f.id.equals(id)))
            .getSingleOrNull();
    if (direct != null) return direct;
    return (select(foods)..where(
          (f) =>
              _ownedCustom(f, ownerUserId) & f.customOriginLocalId.equals(id),
        ))
        .getSingleOrNull();
  }

  Future<Food?> unresolvedCustomByRequest(
    String requestId, {
    required String ownerUserId,
  }) =>
      (select(foods)..where(
            (f) =>
                _ownedCustom(f, ownerUserId) &
                f.customClientRequestId.equals(requestId) &
                f.customSyncPending,
          ))
          .getSingleOrNull();

  /// 全量可见食物（语音录入词典构建用，不做 limit 截断）。
  Future<List<Food>> allFoods({String ownerUserId = 'anonymous'}) {
    return (select(foods)..where((f) => _visibleTo(f, ownerUserId))).get();
  }

  /// 批量写入（食物库初始化/下行刷新用）。
  Future<void> upsertAll(List<FoodsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(foods, entries);
    });
  }

  /// 待上行的当前 owner 自定义食物；旧 null 行须先认领，不跨账号扫描。
  Future<List<Food>> pendingCustomFoods({String ownerUserId = 'anonymous'}) {
    return (select(
      foods,
    )..where((f) => _ownedCustom(f, ownerUserId) & f.customSyncPending)).get();
  }

  Future<void> freezeLegacyCustomCreate(
    String id, {
    required String ownerUserId,
    required String snapshot,
    required String originLocalId,
  }) =>
      (update(foods)..where(
            (f) =>
                _ownedCustom(f, ownerUserId) &
                f.id.equals(id) &
                f.customCreateRequestSnapshot.isNull() &
                f.customClientRequestId.equals('').not(),
          ))
          .write(
            FoodsCompanion(
              customCreateRequestSnapshot: Value(snapshot),
              customOriginLocalId: Value(originLocalId),
            ),
          );

  /// 旧库 null owner 仅由首次登录调用方确定性认领，不在 schema 升级时删改。
  Future<int> claimLegacyCustomFoods(String userId) {
    return (update(foods)..where((f) => f.isCustom & f.ownerUserId.isNull()))
        .write(FoodsCompanion(ownerUserId: Value(userId)));
  }

  /// 匿名个人食物随登录换挂；共享食物不受此 UPDATE 影响。
  Future<int> reassignCustomFoodOwner(String fromUserId, String toUserId) {
    return (update(foods)..where((f) => _ownedCustom(f, fromUserId))).write(
      FoodsCompanion(ownerUserId: Value(toUserId)),
    );
  }

  /// 自定义食物上行成功：清除 pending、幂等键与失败标记。
  Future<void> markCustomSynced(
    String id, {
    required String ownerUserId,
    int? sentVersion,
  }) {
    return (update(foods)..where(
          (f) =>
              _ownedCustom(f, ownerUserId) &
              f.id.equals(id) &
              (sentVersion == null
                  ? const Constant(true)
                  : f.customLocalVersion.equals(sentVersion)),
        ))
        .write(
          const FoodsCompanion(
            customSyncPending: Value(false),
            customClientRequestId: Value(''),
            customCreateRequestSnapshot: Value(null),
            customSyncFailCount: Value(0),
            customSyncFailed: Value(false),
          ),
        );
  }

  /// 明确永久业务失败的计数/终态标记回写（限定当前 owner）。
  Future<void> writeCustomSyncFailure(
    String id, {
    required String ownerUserId,
    required int failCount,
    required bool failed,
    int? sentVersion,
  }) {
    return (update(foods)..where(
          (f) =>
              _ownedCustom(f, ownerUserId) &
              f.id.equals(id) &
              (sentVersion == null
                  ? const Constant(true)
                  : f.customLocalVersion.equals(sentVersion)),
        ))
        .write(
          FoodsCompanion(
            customSyncFailCount: Value(failCount),
            customSyncFailed: Value(failed),
          ),
        );
  }

  /// 手动重试复位（pending=true、失败计数与终态标记清零）。
  Future<void> resetCustomSyncFailure(
    String id, {
    required String ownerUserId,
  }) {
    return (update(
      foods,
    )..where((f) => _ownedCustom(f, ownerUserId) & f.id.equals(id))).write(
      const FoodsCompanion(
        customSyncPending: Value(true),
        customSyncFailCount: Value(0),
        customSyncFailed: Value(false),
      ),
    );
  }

  /// Bind a confirmed create identity without swallowing a newer local edit.
  Future<void> acknowledgeCustomCreate(
    String id, {
    required String ownerUserId,
    required int sentVersion,
  }) async {
    await (update(foods)..where(
          (f) =>
              _ownedCustom(f, ownerUserId) &
              f.id.equals(id) &
              f.customClientRequestId.equals('').not(),
        ))
        .write(
          const FoodsCompanion(
            customClientRequestId: Value(''),
            customCreateRequestSnapshot: Value(null),
            customSyncFailCount: Value(0),
            customSyncFailed: Value(false),
          ),
        );
    await markCustomSynced(
      id,
      ownerUserId: ownerUserId,
      sentVersion: sentVersion,
    );
  }

  /// Merge a concurrently downloaded server row, update references, then remove
  /// the temporary row in the same transaction. Latest local intent wins.
  Future<void> remapCustomFoodId(
    String localId,
    String serverId, {
    required String ownerUserId,
  }) => db.transaction(() async {
    checkActiveSession();
    final local = await getById(localId, ownerUserId: ownerUserId);
    checkActiveSession();
    if (local == null || !local.isCustom || local.ownerUserId != ownerUserId) {
      return;
    }
    final existing = await getById(serverId);
    checkActiveSession();
    if (existing != null &&
        existing.isCustom &&
        existing.ownerUserId != ownerUserId) {
      throw StateError('Cannot remap a food owned by another account');
    }
    await upsertAll([
      local
          .toCompanion(false)
          .copyWith(
            id: Value(serverId),
            customOriginLocalId: Value(local.customOriginLocalId ?? localId),
          ),
    ]);
    checkActiveSession();
    await db.foodEntryDao.remapFoodId(localId, serverId);
    checkActiveSession();
    await deleteById(localId, ownerUserId: ownerUserId, customOnly: true);
    checkActiveSession();
  });

  /// 写入共享贡献审核状态；传 owner 时仅共享行或本人个人行可写。
  Future<void> setContributionStatus(
    String id,
    String? status, {
    String? ownerUserId,
  }) {
    final statement = update(foods)..where((f) => f.id.equals(id));
    if (ownerUserId != null) {
      statement.where((f) => _visibleTo(f, ownerUserId));
    }
    return statement.write(FoodsCompanion(contributionStatus: Value(status)));
  }

  /// 当前账号可见的贡献行：共享行全局，个人行严格按 owner 过滤。
  Future<List<Food>> contributedRows({String ownerUserId = 'anonymous'}) {
    return (select(foods)..where(
          (f) => f.contributionStatus.isNotNull() & _visibleTo(f, ownerUserId),
        ))
        .get();
  }

  /// 占位行（名称==id 双列）：下行记录引用的食物行本地缺失时合成的占位
  ///（见 RemoteRecordSync._ensurePlaceholderFood）。占位回查/存量自愈扫描用。
  Future<List<Food>> placeholderRows() async {
    final rows = await db
        .customSelect(
          'SELECT * FROM foods WHERE name_zh = id AND name_en = id',
          readsFrom: {foods},
        )
        .get();
    return rows.map((row) => foods.map(row.data)).toList();
  }

  /// 物理删除食物行。管理端不传 owner 保持原权限；个人删除必须传
  /// ownerUserId + customOnly，避免跨账号或误删共享行。
  Future<void> deleteById(
    String id, {
    String? ownerUserId,
    bool customOnly = false,
  }) {
    final statement = delete(foods)..where((f) => f.id.equals(id));
    if (ownerUserId != null) {
      statement.where((f) => _visibleTo(f, ownerUserId));
    }
    if (customOnly) {
      statement.where((f) => f.isCustom);
    }
    return statement.go();
  }

  /// 批量删除（seed 版本收敛：上一版有、本版删掉的行）。自定义行由调用方
  /// 过滤（isCustom=false 条件在 seed loader 侧拼）——个人库行不受 seed 管治。
  /// 只删未被 food_entries 引用的（历史记录快照显示不依赖此行，但 FK 约束
  /// 下引用行删除会违约；被引用的残差行留着无害）。
  Future<void> deleteBuiltInByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    // 引用集合走裸 SQL：FoodDao 只挂 foods 表，跨表 DISTINCT 用
    // customSelect 最省（food_entries 生成列名 food_id）。
    final rows = await db
        .customSelect('SELECT DISTINCT food_id FROM food_entries')
        .get();
    final refSet = rows.map((r) => r.read<String>('food_id')).toSet();
    final targets = ids.where((id) => !refSet.contains(id)).toList();
    if (targets.isEmpty) return;
    // Android 11 及以下 SQLite 变量上限 999：7000+ id 单条 isIn 直接
    // too many SQL variables 崩导入，按 500 分块（与 seed upsert 同口径）。
    for (var i = 0; i < targets.length; i += 500) {
      final chunk = targets.sublist(
        i,
        i + 500 > targets.length ? targets.length : i + 500,
      );
      await (delete(
        foods,
      )..where((f) => f.id.isIn(chunk) & f.isCustom.equals(false))).go();
    }
  }
}
