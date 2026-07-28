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
}
