import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'food_dao.g.dart';

/// Food 食物库 DAO（D-16：中英双语条目 + 别名搜索）。
@DriftAccessor(tables: <Type>[Foods])
class FoodDao extends DatabaseAccessor<AppDatabase> with _$FoodDaoMixin {
  FoodDao(super.db);

  /// 双语模糊搜索：中文名/英文名/中文别名/英文别名 LIKE 匹配，
  /// 空串返回前 [limit] 条（常吃/浏览占位）。
  Future<List<Food>> searchFoods(String query, {int limit = 20}) {
    final keyword = query.trim();
    final statement = select(foods)..limit(limit);
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

  /// 按主键取食物（份量换算营养快照用）。
  Future<Food?> getById(String id) {
    return (select(foods)..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  /// 全量食物（语音录入词典构建用：食物库量级约 7.5k 条，内存可行，
  /// 不做 limit 截断——截断会让尾部词条永远匹配不到）。
  Future<List<Food>> allFoods() {
    return select(foods).get();
  }

  /// 批量写入（食物库初始化/下行刷新用）。
  Future<void> upsertAll(List<FoodsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(foods, entries);
    });
  }

  /// 待上行的自定义食物（离线保存 pending，联网后重试 /foods/custom）。
  Future<List<Food>> pendingCustomFoods() {
    return (select(
      foods,
    )..where((f) => f.isCustom & f.customSyncPending)).get();
  }

  /// 自定义食物上行成功：清除 pending 标记。
  Future<void> markCustomSynced(String id) {
    return (update(foods)..where((f) => f.id.equals(id))).write(
      const FoodsCompanion(customSyncPending: Value(false)),
    );
  }

  /// 离线自定义食物上行成功后重映射主键：本地临时 id（custom-*）改写为
  /// 服务端 id 并清除 pending；引用级联（food_entries.foodId）由调用方
  /// 同事务更新（见 CustomFoodRepository.retryPending）。
  Future<void> remapCustomFoodId(String localId, String serverId) {
    return (update(foods)..where((f) => f.id.equals(localId))).write(
      FoodsCompanion(
        id: Value(serverId),
        customSyncPending: const Value(false),
        customClientRequestId: const Value(''),
      ),
    );
  }

  /// 写入共享贡献审核状态（贡献成功/拒收时落本地，搜索行状态标签数据源）。
  Future<void> setContributionStatus(String id, String status) {
    return (update(foods)..where((f) => f.id.equals(id))).write(
      FoodsCompanion(contributionStatus: Value(status)),
    );
  }

  /// 物理删除食物行（自定义食物删除用；调用方须先处理引用它的
  /// food_entries——两态删除/tombstone 由 CustomFoodRepository.delete 负责）。
  Future<void> deleteById(String id) {
    return (delete(foods)..where((f) => f.id.equals(id))).go();
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
