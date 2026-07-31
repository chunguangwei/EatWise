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

  /// 写入共享贡献审核状态（贡献成功/拒收时落本地，搜索行状态标签数据源）。
  Future<void> setContributionStatus(String id, String status) {
    return (update(foods)..where((f) => f.id.equals(id))).write(
      FoodsCompanion(contributionStatus: Value(status)),
    );
  }
}
