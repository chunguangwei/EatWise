import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/application/contribution_review.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 匿名 → 登录数据换挂迁移器（联动审计#1）。
///
/// 盲区成因：未登录期产生的记录全部落在 `userId = 'anonymous'` 名下，
/// 登录成功后各读取侧按真实 userId 查询直接假空，pending 也永远不会
/// 被同步引擎（按真实 userId 扫队列）捞起上行——试用几天再注册的
/// 用户"数据全丢"。
///
/// 策略（与 `daily_nutrition_cache_repair` 的 prefs 标记幂等模式同法）：
/// 登录态 [migrateIfNeeded] 在 syncNow 开头执行一次——
/// - drift 四表 UPDATE userId `anonymous`→真实 uid（FoodEntries /
///   WaterLogs / ExerciseLogs / FastingRecords；已 synced 行也换挂，
///   它们本就属于该用户）。serverId 冲突理论不存在：匿名期服务端没有
///   该用户的任何数据，下行行不会与匿名行同属双方，无需去重合并；
/// - prefs 命名空间换挂：体重日志（同日以已登录侧为准）、贡献审核
///   状态/通知、streak 三键（引擎快照/弹窗频控/幂等键表）各 Store 的
///   静态 `migrateAnonymous` 收口；
/// - 匿名聚合缓存行随记录换主成为孤儿，直接清空（回填修复/入账重算
///   会在本轮同步后立即补建真实 uid 侧缓存）。
///
/// 幂等：每用户一次标记 `anon_migrated_v1_<uid>`（标记先于迁移落盘，
/// 半途失败下次启动不再重试——drift UPDATE 与 prefs 换挂各自也是
/// 幂等/一次性语义，重复执行无害）。
class AnonymousDataMigrator {
  AnonymousDataMigrator({required this.db, required this.prefs});

  /// 本地数据库。
  final AppDatabase db;

  /// prefs（幂等标记 + 各 Store 命名空间换挂）。
  final SharedPreferences prefs;

  /// 迁移完成标记前缀（每用户一次，与 `_cacheBackfillDonePrefix` 同法）。
  static const String _doneKeyPrefix = 'anon_migrated_v1_';

  /// 匿名归属标记（与记录仓储口径一致）。
  static const String anonymousUserId = 'anonymous';

  /// 登录态迁移入口：匿名态 / 已迁移过为 no-op。返回是否执行了迁移。
  ///
  /// 失败上抛（调用方静默吞掉，不阻断同步主链；标记未落则下轮重试）。
  Future<bool> migrateIfNeeded(String userId) async {
    if (userId == anonymousUserId) return false;
    final doneKey = '$_doneKeyPrefix$userId';
    if (prefs.getBool(doneKey) == true) return false;
    // 标记先行：半途异常也不反复重跑（各步本身幂等，重跑也无害，
    // 但避免坏数据导致的每轮同步重试风暴）。
    await prefs.setBool(doneKey, true);
    await _reassignDrift(userId);
    WeightLogStore.migrateAnonymous(prefs, userId);
    ContributionStatusStore.migrateAnonymous(prefs, userId);
    SharedPreferencesStreakLocalStore.migrateAnonymous(prefs, userId);
    return true;
  }

  Future<void> _reassignDrift(String userId) async {
    await db.foodEntryDao.reassignUser(anonymousUserId, userId);
    await db.waterLogDao.reassignUser(anonymousUserId, userId);
    await db.exerciseLogDao.reassignUser(anonymousUserId, userId);
    await db.fastingRecordDao.reassignUser(anonymousUserId, userId);
    // 匿名侧聚合缓存是换挂记录的孤儿派生行：清空防退回匿名后假显；
    // 真实 uid 侧缓存由本轮 _repairDailyCaches 全量回填补建。
    await db.foodEntryDao.deleteUserDailyCaches(anonymousUserId);
  }
}
