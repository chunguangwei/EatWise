import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/time/calendar_day.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;

/// 每日聚合缓存回填修复（v1.12.5 真机走查盲区）。
///
/// 盲区成因：`daily_nutrition_caches`（首页今日汇总/信号卡与数据页近 7 日
/// 趋势的共同数据源）此前只在本地入账/撤销与 sync 下行**有新变更**时重算；
/// 旧版本（v1.12.4 及更早）已下行落库的记录，sync 游标已越过——升级后
/// pull 无新变更，这些存量归属日的缓存永远缺失/过期，首页与趋势假空且
/// 不自愈。
///
/// 修复策略（recompute 本身幂等，两处触发均走后台不同步 build 路径）：
/// - [repairAll]：全量一次性回填（每用户每安装一次，prefs 标记由调用方管）；
/// - [repairRecent]：近 7 天 + 今天的廉价校验窗口（每次 syncNow 后跑，
///   兜住标记后新增的边缘情况）。
class DailyNutritionCacheRepair {
  DailyNutritionCacheRepair({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// 本地数据库。
  final AppDatabase db;

  final DateTime Function() _clock;

  /// 全量回填：记录与缓存日期并集内，缺失/过期/空日残留的缓存全部重算。返回重算天数。
  Future<int> repairAll(String userId) => _repair(userId);

  /// 近 [days] 天（含今天）廉价校验：窗口内缓存缺失/过期才重算。返回重算天数。
  Future<int> repairRecent(String userId, {int days = 7}) {
    final from = addCalendarDays(_clock().toLocal(), 1 - days);
    return _repair(userId, fromDate: localDateKey(from));
  }

  Future<int> _repair(String userId, {String? fromDate}) async {
    checkActiveSession();
    final dates = await db.foodEntryDao.datesWithNutritionData(
      userId,
      fromDate: fromDate,
    );
    var repaired = 0;
    final nowIso = _clock().toUtc().toIso8601String();
    for (final date in dates) {
      checkActiveSession();
      final changed = await db.transaction(() async {
        checkActiveSession();
        if (!await _needsRepair(userId, date)) return false;
        await db.foodEntryDao.recomputeDailyNutrition(
          userId,
          date,
          updatedAtUtc: nowIso,
        );
        checkActiveSession();
        return true;
      });
      if (changed) repaired++;
    }

    return repaired;
  }

  /// 过期判定：缓存缺失，或缓存 updatedAtUtc 早于该日记录的最新修改时间
  /// （ISO8601 UTC 字典序可比；entries 比 cache 新即过期）。
  Future<bool> _needsRepair(String userId, String localDate) async {
    final cache = await db.foodEntryDao.getDailyNutrition(userId, localDate);
    if (cache == null) return true;
    final maxUpdated = await db.foodEntryDao.maxEntryUpdatedAt(
      userId,
      localDate,
    );
    if (maxUpdated == null) {
      // 记录已物理删/全是 tombstone，仍有非零缓存就是旧版中断残留。
      // 保留零值缓存，避免后续每次同步重复修复同一天。
      return cache.entryCount != 0 ||
          cache.kcal != 0 ||
          cache.proteinG != 0 ||
          cache.carbG != 0 ||
          cache.fatG != 0;
    }
    return cache.updatedAtUtc.compareTo(maxUpdated) < 0;
  }
}
