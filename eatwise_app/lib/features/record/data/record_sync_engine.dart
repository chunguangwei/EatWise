import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/application/contribution_review.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
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

  static const String _tokenKeyPrefix = 'record_sync_token_';

  String get _tokenKey => '$_tokenKeyPrefix${repository.userId}';

  bool _syncing = false;

  /// 触发一轮同步（并发去抖：在途时直接返回）。
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      try {
        // 自定义食物先上行（饮食记录引用其服务端 id，颠倒顺序会让
        // 引用本地临时 id 的记录上行 4xx）。
        await customFoodSync?.retryPending();
      } on ApiException {
        // 失败保留下次重试。
      }
      // 贡献审核状态感知（仅登录态）先于记录上行：approved 去「审核中」
      // 标记；rejected 清理本地记录（含 pending，防驳回后上行重建）并入队
      // 一次性驳回通知。失败不阻塞记录上行。
      if (repository.userId != 'anonymous') {
        try {
          await contributionReviewSync?.syncNow();
        } on ApiException {
          // 失败保留下次重试。
        }
      }
      await repository.retryPending();
      await waterSync?.pushPending(repository.db, repository.userId);
      // 体重记录推拉（阶段 C）：仅登录态（匿名推送必 401，本地已可用）。
      final weightSync = this.weightSync;
      final weightStore = this.weightStore;
      if (weightSync != null &&
          weightStore != null &&
          repository.userId != 'anonymous') {
        try {
          await weightSync.sync(weightStore);
        } on ApiException {
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
      }
    } on ApiException {
      // 网络/服务端失败：保持现状，下次触发重试（§4.2）。
    } finally {
      _syncing = false;
    }
  }
}
