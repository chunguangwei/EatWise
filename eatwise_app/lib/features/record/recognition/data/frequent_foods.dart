import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';

/// 常吃复用（PRD M3：基于用户历史高频食物 Top N，点选即填充结果卡）。
///
/// 用 drift customSelect 在 food_entries ⋈ foods 上聚合，不改动
/// core/storage 既有 DAO（查询归属本特性目录）。
final class FrequentFoodsQuery {
  const FrequentFoodsQuery(this.db);

  /// 本地库。
  final AppDatabase db;

  /// 历史高频 Top [limit]：按录入次数降序，次数相同按最近录入时间降序；
  /// 排除 tombstone（deleted）与其他用户的记录。
  Future<List<Food>> topFrequent(String userId, {int limit = 10}) {
    final query = db.customSelect(
      'SELECT f.* FROM food_entries e '
      'JOIN foods f ON f.id = e.food_id '
      'WHERE e.user_id = ? AND e.deleted = 0 '
      'GROUP BY e.food_id '
      'ORDER BY COUNT(*) DESC, MAX(e.created_at_utc) DESC '
      'LIMIT ?',
      variables: <Variable<Object>>[
        Variable<String>(userId),
        Variable<int>(limit),
      ],
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
        db.foodEntries,
        db.foods,
      },
    );
    return query.map((row) => db.foods.map(row.data)).get();
  }
}
