import 'dart:convert';

import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/contribution_review_logic.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 贡献审核状态本地存储（按用户命名空间，与 WeightLogStore 同法）。
///
/// - 已知状态表（candidateId → 上次同步状态）：pending→终态迁移 diff 基线；
/// - 待提示驳回通知队列（食物名列表）：状态迁移时追加，记录页下次展示时
///   取走并清空（一次性提示，跨页面生命周期不丢）。
final class ContributionStatusStore {
  ContributionStatusStore(SharedPreferences prefs, {this.userId = 'anonymous'})
    : readFn = prefs.getString,
      writeFn = prefs.setString;

  ContributionStatusStore._({
    required this.userId,
    required this.readFn,
    required this.writeFn,
  });

  /// 内存兜底：SharedPreferences 未装配（测试/预览）时降级，进程内有效。
  factory ContributionStatusStore.inMemory({String userId = 'anonymous'}) {
    final box = <String, String>{};
    return ContributionStatusStore._(
      userId: userId,
      readFn: (String key) => box[key],
      writeFn: (String key, String value) async {
        box[key] = value;
        return true;
      },
    );
  }

  static const String _statusPrefix = 'record.contributionStatus.v1.';
  static const String _noticePrefix = 'record.rejectedNotices.v1.';

  /// 归属用户（未登录 anonymous，与记录仓储口径一致）。
  final String userId;

  final String? Function(String key) readFn;
  final Future<bool> Function(String key, String value) writeFn;

  String get _statusKey => '$_statusPrefix$userId';
  String get _noticeKey => '$_noticePrefix$userId';

  /// 已知状态表（candidateId → status 字符串；脏数据按空表处理）。
  Map<String, String> loadKnown() {
    final raw = readFn(_statusKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on FormatException {
      return <String, String>{};
    }
  }

  /// 全量覆写已知状态表。
  Future<void> saveKnown(Map<String, String> known) {
    return writeFn(_statusKey, jsonEncode(known));
  }

  /// 追加驳回通知（食物展示名）。
  Future<void> appendNotices(List<String> names) async {
    if (names.isEmpty) return;
    final pending = _loadNotices()..addAll(names);
    await writeFn(_noticeKey, jsonEncode(pending));
  }

  /// 取走全部待提示通知并清空（一次性提示）。
  Future<List<String>> drainNotices() async {
    final pending = _loadNotices();
    if (pending.isNotEmpty) await writeFn(_noticeKey, '[]');
    return pending;
  }

  List<String> _loadNotices() {
    final raw = readFn(_noticeKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.whereType<String>().toList();
    } on FormatException {
      return <String>[];
    }
  }
}

/// 贡献审核状态同步（不做推送：记录同步 / 进入记录页时拉取「我的贡献」，
/// 与本地已知状态 diff）：
/// - pending → approved：条目转正——本地食物行 contributionStatus 置 approved
///   （今日记录「审核中」徽标消失；条目营养为入账快照，不回溯重算）；
/// - pending → rejected：清除该食物的本用户全部本地记录（物理删除；已上行的
///   由服务端 reject 级联软删 + sync/pull tombstone 收敛，本地删除不 resurrect）
///   并按日重算聚合，食物行标记 rejected，追加一次性驳回通知。
///
/// 首次同步（本地无基线）静默纳入，不把历史终态当新事件提示。
final class ContributionReviewSync {
  ContributionReviewSync({
    required this.db,
    required this.remote,
    required this.store,
    this.userId = 'anonymous',
    this.onNoticesAdded,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 本地库。
  final AppDatabase db;

  /// 远程端（生产 RemoteCustomFoodApi；测试 Fake）。
  final CustomFoodRemote remote;

  /// 状态/通知本地存储（当前用户命名空间）。
  final ContributionStatusStore store;

  /// 归属用户（anonymous 直接跳过：贡献需登录，匿名无候选）。
  final String userId;

  /// 有新驳回通知入队后的回调（UI 层 bump tick 触发展示）。
  final void Function()? onNoticesAdded;

  final DateTime Function() _clock;

  bool _syncing = false;

  /// 拉取一轮并应用状态迁移；返回本轮新产生的驳回通知（食物名）。
  /// 并发去抖；网络/业务异常上抛由调用方容错（保持现状下轮重试）。
  Future<List<String>> syncNow() async {
    if (_syncing || userId == 'anonymous') return const <String>[];
    _syncing = true;
    try {
      final current = await _fetchAll();
      final known = store.loadKnown();
      final transitions = diffContributionTransitions(known, current);
      final notices = <String>[];
      for (final t in transitions) {
        switch (t.to) {
          case FoodContributionStatus.approved:
            await db.foodDao.setContributionStatus(t.foodId, 'approved');
          case FoodContributionStatus.rejected:
            notices.add(await _applyRejection(t.foodId));
          case FoodContributionStatus.pending:
            break; // diff 只产出终态迁移，防御性穷尽
        }
      }
      await store.saveKnown(knownStatusMapOf(current));
      if (notices.isNotEmpty) {
        await store.appendNotices(notices);
        onNoticesAdded?.call();
      }
      return notices;
    } finally {
      _syncing = false;
    }
  }

  /// 全量拉取我的贡献（页码翻页直到 hasMore=false）。
  Future<List<FoodContribution>> _fetchAll() async {
    final all = <FoodContribution>[];
    var page = 1;
    while (true) {
      final result = await remote.getContributions(page: page, pageSize: 50);
      all.addAll(result.items);
      if (!result.hasMore) return all;
      page += 1;
    }
  }

  /// 驳回落地：删记录 + 重算聚合 + 标记食物；返回通知用的食物展示名
  ///（食物行缺失回退 foodId，不隐藏事件）。
  Future<String> _applyRejection(String foodId) async {
    final food = await db.foodDao.getById(foodId);
    final entries = await db.foodEntryDao.entriesForFood(userId, foodId);
    final dates = <String>{};
    for (final entry in entries) {
      await db.foodEntryDao.deleteEntry(entry.localId);
      dates.add(entry.localDate);
    }
    final nowIso = _clock().toUtc().toIso8601String();
    for (final date in dates) {
      await db.foodEntryDao.recomputeDailyNutrition(
        userId,
        date,
        updatedAtUtc: nowIso,
      );
    }
    await db.foodDao.setContributionStatus(foodId, 'rejected');
    return food?.nameZh ?? foodId;
  }
}
