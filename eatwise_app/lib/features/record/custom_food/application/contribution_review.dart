import 'dart:convert';

import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/contribution_review_logic.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 贡献审核状态本地存储（按用户命名空间，与 WeightLogStore 同法）。
///
/// - 已知状态表（candidateId → 上次同步状态）：pending→终态迁移 diff 基线；
/// - 待提示驳回通知队列（食物名 + correction 标记）：状态迁移时追加，
///   记录页下次展示时取走清空。

/// 驳回一次性通知（食物展示名 + 是否纠错类：correction 驳回不动记录，
/// 文案区分）。
final class RejectedNotice {
  const RejectedNotice({
    required this.name,
    this.correction = false,
    this.removed = false,
  });

  final String name;
  final bool correction;

  /// 管理员删除审核内容（下架/清痕迹）触发，非审核驳回——文案区分。
  final bool removed;
}

/// 贡献审核状态本地存储（按用户命名空间，与 WeightLogStore 同法）。
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

  /// 追加通知（食物展示名 + 是否纠错类 + 是否管理员下架——文案区分
  /// 「记录已移除」「数据未改动」「已下架」）。落库三元组。
  Future<void> appendNotices(List<RejectedNotice> notices) async {
    if (notices.isEmpty) return;
    final pending = _loadNotices()..addAll(notices);
    await writeFn(
      _noticeKey,
      jsonEncode(<List<Object?>>[
        for (final n in pending) <Object?>[n.name, n.correction, n.removed],
      ]),
    );
  }

  /// 取走全部待提示通知并清空（一次性提示）。
  Future<List<RejectedNotice>> drainNotices() async {
    final pending = _loadNotices();
    if (pending.isNotEmpty) await writeFn(_noticeKey, '[]');
    return pending;
  }

  List<RejectedNotice> _loadNotices() {
    final raw = readFn(_noticeKey);
    if (raw == null || raw.isEmpty) return <RejectedNotice>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <RejectedNotice>[];
      // 兼容读：v1 纯字符串 / v2 二元组 [name, correction] / v3 三元组。
      return decoded
          .map(
            (final e) => switch (e) {
              final String name => RejectedNotice(name: name),
              [final Object? name, final Object? correction]
                  when name is String =>
                RejectedNotice(name: name, correction: correction == true),
              [
                final Object? name,
                final Object? correction,
                final Object? removed,
              ]
                  when name is String =>
                RejectedNotice(
                  name: name,
                  correction: correction == true,
                  removed: removed == true,
                ),
              _ => null,
            },
          )
          .nonNulls
          .toList();
    } on FormatException {
      return <RejectedNotice>[];
    }
  }

  /// 登录换挂（审计#1 匿名数据迁移）：anonymous 命名空间并入 [userId]
  /// 命名空间后删除匿名键。口径：已知状态表（candidateId → 状态）同候选
  /// 以已登录侧为准（uid 侧 diff 基线更新），驳回通知队列按「uid 侧在前、匿名侧追加」
  /// 合并（一次性提示不丢失）。匿名期审核同步本不运行（引擎登录态
  /// 门禁），此换挂兜住旧版本遗留的匿名键。
  static void migrateAnonymous(SharedPreferences prefs, String userId) {
    for (final prefix in <String>[_statusPrefix, _noticePrefix]) {
      final anonKey =
          '$prefix'
          'anonymous';
      final raw = prefs.getString(anonKey);
      if (raw == null || raw.isEmpty) continue;
      final targetKey = '$prefix$userId';
      final ownRaw = prefs.getString(targetKey);
      var merged = raw;
      if (prefix == _statusPrefix) {
        final map = <String, Object?>{};
        for (final src in <String?>[raw, ownRaw]) {
          if (src == null || src.isEmpty) continue;
          try {
            final decoded = jsonDecode(src);
            // uid 侧在第二轮：同候选（键）覆盖匿名侧。
            if (decoded is Map) {
              for (final e in decoded.entries) {
                if (e.value is String) map[e.key.toString()] = e.value;
              }
            }
          } on FormatException {
            // 脏键忽略。
          }
        }
        merged = jsonEncode(map);
      } else {
        // 通知元素两种格式（旧 String / 新 [name, correction]）原样搬运，
        // 解析延迟到 _loadNotices。
        final list = <Object?>[];
        for (final src in <String?>[ownRaw, raw]) {
          if (src == null || src.isEmpty) continue;
          try {
            final decoded = jsonDecode(src);
            if (decoded is List) list.addAll(decoded);
          } on FormatException {
            // 脏键忽略。
          }
        }
        merged = jsonEncode(list);
      }
      // 同步写穿内存缓存（setString 返回前已生效），fire-and-forget。
      prefs.setString(targetKey, merged);
      prefs.remove(anonKey);
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
    this.onStatusApplied,
    this.existingFoodIdsFn,
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

  /// 本地食物行 contributionStatus 被本轮改写后的回调（UI 层 invalidate
  /// entryFoodProvider——记录行「审核中」徽标的数据源是一次性 FutureProvider
  /// 缓存，不失效则本会话内徽标永不消失，真机走查缺陷）。
  final void Function(String foodId)? onStatusApplied;

  /// 幽灵共享行服务端核验（v1.13.18 走查：管理台手工软删的共享行本地
  /// 滞留）。仅当本轮存在非自定义幽灵行时调用（罕见且廉价）；返回服务端
  /// 仍存在的 id 集合（生产 = POST /foods/batch-get 命中集）。
  /// null = 未装配/不核验（保持旧口径：共享行只清徽标）；调用异常同上。
  final Future<Set<String>> Function(List<String> foodIds)? existingFoodIdsFn;

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
      final notices = <RejectedNotice>[];
      for (final t in transitions) {
        switch (t.to) {
          case FoodContributionStatus.approved:
            await db.foodDao.setContributionStatus(t.foodId, 'approved');
            onStatusApplied?.call(t.foodId);
          case FoodContributionStatus.rejected:
            // 纠错驳回：目标食物仍在共享库、记录不动（服务端同口径）——
            // 只提示「建议未采纳」；自定义/条码驳回才清记录（走查修复：
            // 旧逻辑误删纠错用户的全部历史饮食）。
            notices.add(
              t.kind == FoodContributionKind.correction
                  ? RejectedNotice(
                      name: await _foodDisplayName(t.foodId),
                      correction: true,
                    )
                  : await _applyRejection(t.foodId),
            );
          case FoodContributionStatus.pending:
            break; // diff 只产出终态迁移，防御性穷尽
        }
      }
      // 存量校正：首轮即终态（无 pending 基线可 diff——管理员在客户端
      // 见到 pending 之前就批完，如提交后秒批 / 离线期间审批）时，本地
      // Foods 行还停在 pending，「审核中」徽标永不清除（真机走查）。
      // 幂等对齐，不提示、不清记录（首轮静默意图不变）。同一食物可能挂
      // 多条贡献（驳回纠错 + 通过自定义），逐条迭代后写覆盖前写、结果随
      // 迭代顺序漂移——按 foodId 取 updatedAt 最新的终态贡献为权威值；
      // 本地行与权威值不一致即改写（覆盖 rejected→approved 重提交残留）。
      final authoritative = <String, FoodContribution>{};
      for (final c in current) {
        if (c.status == FoodContributionStatus.pending) continue;
        if (known[c.id] == 'pending') continue; // 终态迁移已在上面处理
        final prev = authoritative[c.foodId];
        if (prev == null || !c.updatedAt.isBefore(prev.updatedAt)) {
          authoritative[c.foodId] = c;
        }
      }
      for (final entry in authoritative.entries) {
        await _reconcileStatus(
          entry.key,
          foodContributionStatusName(entry.value.status),
        );
      }
      // 已下架收敛（走查②「服务端删了客户端还在」）：行级反查——本地带
      // 贡献状态的自定义行不在服务端「我的贡献」foodId 全集 = 管理员已删
      // 审核内容（候选行消失，状态 diff 无从感知）。清记录 + 删行 +
      // 下架通知；共享行（isCustom=false）先清徽标，再经
      // [existingFoodIdsFn] 核验服务端存续决定整行移除（见下）。
      final serverFoodIds = <String>{for (final c in current) c.foodId};
      final ghosts = findGhostContributionFoodIds(
        localRows: (await db.foodDao.contributedRows()).map(
          (final r) => (id: r.id, contributionStatus: r.contributionStatus),
        ),
        serverFoodIds: serverFoodIds,
      );
      final sharedGhosts = <String>{};
      for (final foodId in ghosts) {
        final row = await db.foodDao.getById(foodId);
        if (row == null) continue;
        if (!row.isCustom) {
          // 共享/社区行：先清徽标残留（纠错终态写在共享行上，候选删除后
          // 徽标须复位）；再核验服务端是否还有此行——管理台/管理员删除后
          // 行已软删（v1.13.18 走查：「已共享」行客户端滞留可搜可点开），
          // 查无此行 → 整行移除（引用记录物理删+聚合重算，静默不通知——
          // 非本人贡献物，下架通知只对贡献者有意义）。
          // 占位行（名称==id，下行合成）永不在此路径（contributionStatus
          // 恒 null 进不了 ghost 集），双保险显式排除。
          await db.foodDao.setContributionStatus(foodId, null);
          onStatusApplied?.call(foodId);
          if (isPlaceholderFood(row)) continue;
          sharedGhosts.add(foodId);
          continue;
        }
        notices.add(await _applyRemoval(foodId, row.nameZh));
      }
      // 幽灵共享行服务端核验：查无此行 → 整行移除（一次性 batch-get，
      // 仅本轮有幽灵时才调，廉价）；核验失败（离线/未装配）保持只清徽标。
      // 合并核验「在列行」（在「我的贡献」集合内 = 非 ghost，但食物行本身
      // 已被管理台手工软删而候选行未删——v1.13.20 走查盲区：「蔬菜沙拉
      // （已共享）」为本人贡献 approved 行，foodId 在集合内永不成 ghost，
      // 旧反查结构性看不到它）：同一批 batch-get，查无 → 自定义行按
      // 下架口径清记录+删行+通知（同管理员删候选），共享行整行静默移除。
      final inListIds = <String>[];
      for (final r in await db.foodDao.contributedRows()) {
        if (serverFoodIds.contains(r.id)) inListIds.add(r.id);
      }
      final verifyIds = <String>{...sharedGhosts, ...inListIds}.toList();
      if (verifyIds.isNotEmpty && existingFoodIdsFn != null) {
        try {
          final existing = await existingFoodIdsFn!(verifyIds);
          for (final foodId in sharedGhosts) {
            if (existing.contains(foodId)) continue;
            final row = await db.foodDao.getById(foodId);
            if (row == null) continue;
            await _removeSharedGhost(foodId);
          }
          for (final foodId in inListIds) {
            if (existing.contains(foodId)) continue;
            final row = await db.foodDao.getById(foodId);
            if (row == null || isPlaceholderFood(row)) continue;
            if (row.isCustom) {
              notices.add(await _applyRemoval(foodId, row.nameZh));
            } else {
              await _removeSharedGhost(foodId);
            }
          }
        } on Object catch (e) {
          // 核验失败：本轮只清徽标，下轮重试。留痕便于真机诊断
          // 「幽灵行为何还在」（batch-get 路由未部署/401/离线都会落这里）。
          debugPrint('[ContributionReview] 幽灵共享行核验失败（下轮重试）：$e');
        }
      }
      await store.saveKnown(knownStatusMapOf(current));
      if (notices.isNotEmpty) {
        await store.appendNotices(notices);
        onNoticesAdded?.call();
      }
      return notices.map((final n) => n.name).toList();
    } finally {
      _syncing = false;
    }
  }

  Future<String> _foodDisplayName(String foodId) async {
    return (await db.foodDao.getById(foodId))?.nameZh ?? foodId;
  }

  /// 本地行存在且状态与权威终态不一致才改写（幂等：已对齐零写入）。
  Future<void> _reconcileStatus(String foodId, String status) async {
    final food = await db.foodDao.getById(foodId);
    if (food != null && food.contributionStatus != status) {
      await db.foodDao.setContributionStatus(foodId, status);
      onStatusApplied?.call(foodId);
    }
  }

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

  /// 驳回落地：删记录 + 重算聚合 + 标记食物；返回驳回通知
  ///（食物行缺失回退 foodId，不隐藏事件）。
  Future<RejectedNotice> _applyRejection(String foodId) async {
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
    onStatusApplied?.call(foodId);
    return RejectedNotice(name: food?.nameZh ?? foodId);
  }

  /// 下架落地（对齐服务端删候选级联：软删记录 + 软删食物行）：删记录 +
  /// 重算聚合 + 删本地食物行；返回下架通知（custom/barcode 内容下架语义，
  /// 记录清法同驳回——tombstone/物理删口径由 foodEntryDao.deleteEntry 承担）。
  Future<RejectedNotice> _applyRemoval(String foodId, String name) async {
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
    await db.foodDao.deleteById(foodId);
    onStatusApplied?.call(foodId);
    return RejectedNotice(name: name, removed: true);
  }

  /// 幽灵共享行整行移除（服务端已删核验后）：引用记录物理删 + 归属日聚合
  /// 重算 + 删行 + 失效名称缓存。静默（不下架通知——非本人贡献物）。
  /// 服务端级联 tombstone 尚未下行的记录：下轮 pull tombstone 对账已无
  /// 本地行，幂等空转。
  Future<void> _removeSharedGhost(String foodId) async {
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
    await db.foodDao.deleteById(foodId);
    onStatusApplied?.call(foodId);
  }
}
