import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/health/data/remote_exercise_log_sync.dart';
import 'package:eatwise/features/record/custom_food/application/contribution_review.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/data/anonymous_data_migrator.dart';
import 'package:eatwise/features/record/data/daily_nutrition_cache_repair.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// 记录同步引擎（规格 §2.1：App 启动 / 前台恢复 / 登录成功触发）。
///
/// 顺序：自定义食物上行 → 贡献审核状态感知 → 饮食/饮水/体重上行 →
/// syncToken 增量下行入库（§2.4，含 waterLogChanges）。
/// - 自定义食物必须先于饮食记录上行——记录引用服务端食物 id，食物未上行
///   时记录上行必败；
/// - 贡献审核感知必须先于饮食记录上行——已驳回食物的本地 pending 记录
///   先清理，避免驳回后上行在服务端重建记录（驳回级联只删驳回时点存量）。
/// 远程端为 Fake（测试/演示注入）时仅做上行重试，下行跳过。
final class RecordSyncEngine {
  RecordSyncEngine({
    required this.repository,
    required this.prefs,
    this.waterSync,
    this.customFoodSync,
    this.weightSync,
    this.weightStore,
    this.contributionReviewSync,
    this.exerciseSync,
    this.planSync,
    this.cacheRepair,
    this.anonymousMigrator,
    this.onFoodsBackfilled,
  });

  /// 记录仓储。
  final RecordRepository repository;

  /// syncToken 持久化。
  final SharedPreferences prefs;

  /// 饮水上行同步（可选：测试/未装配场景为 null 跳过）。
  final RemoteWaterLogSync? waterSync;

  /// 自定义食物上行重试（可选：未装配为 null 跳过）。
  final CustomFoodRepository? customFoodSync;

  /// 体重记录推拉同步（可选：阶段 C；与 [weightStore] 成对装配）。
  final RemoteWeightLogSync? weightSync;

  /// 体重本地存储（当前用户命名空间）。
  final WeightLogStore? weightStore;

  /// 贡献审核状态同步（可选：未装配/匿名跳过；仅登录态有意义）。
  final ContributionReviewSync? contributionReviewSync;

  /// 运动记录上行同步（可选：2026-09-19 拍板上行；未装配为 null 跳过）。
  final RemoteExerciseLogSync? exerciseSync;

  /// 断食方案上行同步（可选：进食窗口自选；未装配为 null 跳过）。
  final FastingPlanSync? planSync;

  /// 每日聚合缓存回填修复（可选：v1.12.5 走查盲区——旧版本下行遗留的
  /// 存量记录不经重算、sync 游标已越过，首页/趋势假空不自愈；未装配为
  /// null 跳过）。
  final DailyNutritionCacheRepair? cacheRepair;

  /// 匿名数据换挂迁移器（可选：审计#1——登录首轮同步前把 anonymous 名下
  /// 记录/prefs 并入真实 uid；未装配为 null 跳过）。
  final AnonymousDataMigrator? anonymousMigrator;

  /// 占位食物行回查补名成功回调（>0 行时触发；调用方失效
  /// entryFoodProvider / recordFoodSearchProvider 等名称缓存）。
  final void Function()? onFoodsBackfilled;

  static const String _tokenKeyPrefix = 'record_sync_token_';

  /// 聚合缓存全量回填完成标记（每用户每安装一次；标记后每次 syncNow
  /// 只跑近 7 天廉价窗口，兜住标记后新增的边缘情况）。
  static const String _cacheBackfillDonePrefix = 'daily_cache_backfill_v1_';

  String get _tokenKey => '$_tokenKeyPrefix${repository.userId}';

  bool _syncing = false;

  /// 触发一轮同步（并发去抖：在途时直接返回）。
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      // 匿名数据换挂（审计#1）先于一切上行/下行：登录首轮把试用期的
      // anonymous 名下记录并入真实 uid（否则 pending 永远不上行、
      // 页面假空）。仅登录态；失败静默（迁移器内部标记未落则下轮重试），
      // 不阻断同步主链。
      if (repository.userId != 'anonymous') {
        try {
          await anonymousMigrator?.migrateIfNeeded(repository.userId);
        } on Object {
          // 迁移失败降级为「维持现状」，下轮 syncNow 重试（标记未落）。
        }
      }
      // 断食方案上行（进食窗口自选）：脏标记存在时 PUT（仅登录态——
      // 匿名必 401，脏标记保留待登录后同步轮迁移上行）。失败保留重试。
      try {
        await planSync?.flush();
      } on Object catch (e) {
        // 失败保留脏标记，下次同步轮重试。捕获放宽到 Object：曾只 catch
        // ApiException，插件/序列化等杂异常直接中断整轮，后面的贡献审核/
        // 记录上行全部轮不到（徽标残留嫌疑路径）。
        debugPrint('[Sync] planSync.flush 失败（下轮重试）：$e');
      }
      try {
        // 自定义食物先上行（饮食记录引用其服务端 id，颠倒顺序会让
        // 引用本地临时 id 的记录上行 4xx）。
        await customFoodSync?.retryPending();
      } on Object catch (e) {
        debugPrint('[Sync] customFood.retryPending 失败（下轮重试）：$e');
      }
      // 贡献审核状态感知（仅登录态）先于记录上行：approved 去「审核中」
      // 标记；rejected 清理本地记录（含 pending，防驳回后上行重建）并入队
      // 一次性驳回通知。失败不阻塞记录上行。
      if (repository.userId != 'anonymous') {
        try {
          await contributionReviewSync?.syncNow();
        } on Object catch (e) {
          // 失败保留下次重试；留痕便于真机诊断徽标残留。
          debugPrint('[Sync] contributionReview.syncNow 失败（下轮重试）：$e');
        }
      }
      await repository.retryPending();
      await waterSync?.pushPending(repository.db, repository.userId);
      // 运动记录上行（2026-09-19 拍板）：与饮水同链（仅登录态——匿名推送
      // 必 401，本地 pending 保留待登录后由登录成功触发的同步轮上行）。
      if (repository.userId != 'anonymous') {
        try {
          await exerciseSync?.pushPending(repository.db, repository.userId);
        } on Object catch (e) {
          debugPrint('[Sync] exercise pushPending 失败（下轮重试）：$e');
          // 失败保留下次重试。
        }
      }
      // 体重记录推拉（阶段 C）：仅登录态（匿名推送必 401，本地已可用）。
      final weightSync = this.weightSync;
      final weightStore = this.weightStore;
      if (weightSync != null &&
          weightStore != null &&
          repository.userId != 'anonymous') {
        try {
          await weightSync.sync(weightStore);
        } on Object catch (e) {
          debugPrint('[Sync] weight sync 失败（下轮重试）：$e');
          // 失败保留下次重试。
        }
      }
      final remote = repository.remote;
      if (remote is RemoteRecordSync) {
        final token = await remote.pullDown(
          repository.db,
          repository.userId,
          prefs.getString(_tokenKey),
        );
        if (token != null) {
          await prefs.setString(_tokenKey, token);
        }
        // 占位食物行回查（仅登录态——batch-get 需 JWT；匿名占位行保留待
        // 登录后同步轮补名）：本轮下行新落的占位 + 存量「名称=foodId」行
        // 一并扫描（升级自愈），命中即写真名，失效 UI 缓存。
        if (repository.userId != 'anonymous') {
          try {
            final resolved = await remote.backfillPlaceholderFoods(
              repository.db,
            );
            if (resolved > 0) onFoodsBackfilled?.call();
          } on Object catch (e) {
            // 失败保留下轮重试（占位行不动，不阻断下行主链）。
            debugPrint('[Sync] placeholder food backfill 失败（下轮重试）：$e');
          }
        }
      }
    } on ApiException {
      // 网络/服务端失败：保持现状，下次触发重试（§4.2）。
    } finally {
      // 聚合缓存存量回填（v1.12.5 走查盲区修复）：**不依赖 pull 有无新
      // 变更，也不依赖在线**——旧版本下行遗留记录游标已越过，缓存永远
      // 不会被重算，必须在每轮同步后主动扫描（纯本地操作，后台执行，
      // recompute 幂等）。首次全量回填（prefs 标记），之后每次只校验
      // 近 7 天廉价窗口。失败静默，下轮 syncNow 重试。
      await _repairDailyCaches();
      _syncing = false;
    }
  }

  Future<void> _repairDailyCaches() async {
    final repair = cacheRepair;
    if (repair == null) return;
    final userId = repository.userId;
    try {
      final doneKey = '$_cacheBackfillDonePrefix$userId';
      if (prefs.getBool(doneKey) != true) {
        await repair.repairAll(userId);
        await prefs.setBool(doneKey, true);
      } else {
        await repair.repairRecent(userId);
      }
    } on Object {
      // 回填失败不阻塞同步主链，下轮 syncNow 重试（标记未落则仍走全量）。
    }
  }
}
