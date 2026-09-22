import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 审批中心远程端（生产 REST；测试 override 为 FakeModerationRemote）。
final Provider<ModerationRemote> moderationRemoteProvider =
    Provider<ModerationRemote>((ref) {
      return RemoteModerationApi(dio: ref.watch(apiDioProvider));
    });

/// 审批中心列表四态。
enum ModerationStatus { loading, ready, error }

/// 审批中心状态（pending 队列 + 游标分页累积）。
final class ModerationState {
  const ModerationState({
    this.status = ModerationStatus.loading,
    this.items = const <ModerationCandidate>[],
    this.nextCursor,
    this.hasMore = false,
    this.loadingMore = false,
    this.actingId,
    this.errorMessage,
  });

  /// 加载态。
  final ModerationStatus status;

  /// 已加载候选（createdAt 升序，先入先审）。
  final List<ModerationCandidate> items;

  /// 下一页游标。
  final String? nextCursor;

  /// 是否还有下一页。
  final bool hasMore;

  /// 翻页进行中。
  final bool loadingMore;

  /// 审核操作在途的候选 id（按钮 loading 防连点）。
  final String? actingId;

  /// 错误信息（首屏失败时展示）。
  final String? errorMessage;

  ModerationState copyWith({
    ModerationStatus? status,
    List<ModerationCandidate>? items,
    String? nextCursor,
    bool? hasMore,
    bool? loadingMore,
    String? actingId,
    String? errorMessage,
    bool clearCursor = false,
    bool clearActing = false,
    bool clearError = false,
  }) {
    return ModerationState(
      status: status ?? this.status,
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      actingId: clearActing ? null : (actingId ?? this.actingId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 审批操作结果（页面据此弹 snackbar）。
enum ModerationActionResult { approved, rejected, deleted }

/// 审批中心控制器（pending 候选队列：游标分页 + 下拉刷新 + 通过/驳回）。
final class ModerationController extends Notifier<ModerationState> {
  static const int pageSize = 20;

  ModerationRemote get _remote => ref.read(moderationRemoteProvider);

  @override
  ModerationState build() {
    unawaited(_loadFirstPage());
    return const ModerationState();
  }

  /// 下拉刷新（重置到第一页）。
  Future<void> refresh() => _loadFirstPage();

  /// 滚动到底加载下一页（游标分页；失败保留已有内容可重试）。
  Future<void> loadMore() async {
    if (state.status != ModerationStatus.ready ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final result = await _remote.listPending(
        cursor: state.nextCursor,
        limit: pageSize,
      );
      final known = state.items.map((c) => c.id).toSet();
      state = state.copyWith(
        items: <ModerationCandidate>[
          ...state.items,
          ...result.items.where((c) => !known.contains(c.id)),
        ],
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
        loadingMore: false,
        clearCursor: result.nextCursor == null,
      );
    } on ApiException {
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 审核（approve/reject）：成功后该候选出队（服务端终态不再出现在
  /// pending 队列，本地直接移除不等整页刷新）；失败上抛由 UI 提示。
  Future<ModerationActionResult> review(
    String candidateId, {
    required bool approve,
    String? reason,
  }) async {
    if (state.actingId != null) {
      throw StateError('review in progress'); // 防连点（按钮已 loading）
    }
    state = state.copyWith(actingId: candidateId);
    try {
      await _remote.review(
        candidateId,
        action: approve ? 'approve' : 'reject',
        reason: reason,
      );
      final hits = state.items.where((c) => c.id == candidateId).toList();
      final candidate = hits.isEmpty ? null : hits.first;
      state = state.copyWith(
        items: state.items.where((c) => c.id != candidateId).toList(),
        clearActing: true,
      );
      if (candidate != null && candidate.foodId.isNotEmpty) {
        await _applyLocalFoodStatus(candidate.foodId, approve);
      }
      return approve
          ? ModerationActionResult.approved
          : ModerationActionResult.rejected;
    } on Object {
      state = state.copyWith(clearActing: true);
      rethrow;
    }
  }

  /// 删除审核内容：成功后该候选出队。同设备既是审批人又是提交人时
  /// （走查场景），本机贡献物立即直清（服务端已级联软删食物行+记录；
  /// 本地 pending/终态行不删=幽灵，与「服务端删了客户端还在」同根）；
  /// 跨设备贡献者由 ContributionReviewSync「已下架收敛」下一轮兜底。
  Future<ModerationActionResult> delete(String candidateId) async {
    if (state.actingId != null) {
      throw StateError('review in progress'); // 防连点（按钮已 loading）
    }
    state = state.copyWith(actingId: candidateId);
    try {
      await _remote.delete(candidateId);
      final hits = state.items.where((c) => c.id == candidateId).toList();
      final candidate = hits.isEmpty ? null : hits.first;
      state = state.copyWith(
        items: state.items.where((c) => c.id != candidateId).toList(),
        clearActing: true,
      );
      if (candidate != null && candidate.foodId.isNotEmpty) {
        await _clearLocalFoodOnDelete(candidate);
      }
      return ModerationActionResult.deleted;
    } on Object {
      state = state.copyWith(clearActing: true);
      rethrow;
    }
  }

  /// 审核终态即时回写本地食物行并失效记录行食物缓存：同设备既是审批人
  /// 又是提交人时（真机走查场景），本机「审核中」徽标不必等下一轮
  /// ContributionReviewSync。只动 contributionStatus==pending 的本地行
  /// （他端提交/共享库行恒 null 不受影响）；失败静默——远端已终态，
  /// 本地由后续同步轮 reconcile 兜底。
  Future<void> _applyLocalFoodStatus(String foodId, bool approve) async {
    try {
      final dao = ref.read(recordRepositoryProvider).db.foodDao;
      final food = await dao.getById(foodId);
      if (food == null || food.contributionStatus != 'pending') return;
      await dao.setContributionStatus(
        foodId,
        approve ? 'approved' : 'rejected',
      );
      ref.invalidate(entryFoodProvider(foodId));
    } on Object {
      // 本地回写失败不影响审核结果。
    }
  }

  /// 删除后的本机直清：correction=目标共享行不动、仅撤徽标（pending 行）；
  /// custom/barcode=服务端已软删行+记录，本地行存在则整行删除 + 记录级联
  /// （两态 deleteEntry 口径由 recordRepository 承担不了——这里行是本人
  /// 贡献物，直接走 foodDao/foodEntryDao 同款清理）。失败静默：远端已删，
  /// 下一轮 ContributionReviewSync 行级反查兜底。
  Future<void> _clearLocalFoodOnDelete(ModerationCandidate candidate) async {
    try {
      final db = ref.read(recordRepositoryProvider).db;
      final food = await db.foodDao.getById(candidate.foodId);
      if (food != null) {
        if (candidate.kind == FoodContributionKind.correction) {
          if (food.contributionStatus != null) {
            await db.foodDao.setContributionStatus(candidate.foodId, null);
          }
        } else if (food.isCustom) {
          final userId = ref.read(currentUserIdProvider);
          final entries = await db.foodEntryDao.entriesForFood(
            userId,
            candidate.foodId,
          );
          final dates = <String>{};
          for (final entry in entries) {
            await db.foodEntryDao.deleteEntry(entry.localId);
            dates.add(entry.localDate);
          }
          final nowIso = DateTime.now().toUtc().toIso8601String();
          for (final date in dates) {
            await db.foodEntryDao.recomputeDailyNutrition(
              userId,
              date,
              updatedAtUtc: nowIso,
            );
          }
          await db.foodDao.deleteById(candidate.foodId);
        }
      }
      ref.invalidate(entryFoodProvider(candidate.foodId));
      // 搜索结果缓存行同步失效（常驻流不会自刷已删行）。
      ref.invalidate(recordFoodSearchProvider);
    } on Object {
      // 本机直清失败不影响删除结果（同步轮兜底）。
    }
    // 顺带触发一轮贡献同步（best-effort：跨设备贡献者 & 队列刷新）。
    try {
      unawaited(
        ref
            .read(contributionReviewSyncProvider)
            .syncNow()
            .catchError((Object _) => <String>[]),
      );
    } on Object {
      // provider 依赖（dio/prefs）未装配的预览环境：忽略。
    }
  }

  Future<void> _loadFirstPage() async {
    try {
      final result = await _remote.listPending(limit: pageSize);
      state = ModerationState(
        status: ModerationStatus.ready,
        items: result.items,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      );
    } on ApiException catch (e) {
      state = ModerationState(
        status: ModerationStatus.error,
        errorMessage: e.message,
      );
    }
  }
}

/// 审批中心 Provider。
final NotifierProvider<ModerationController, ModerationState>
moderationControllerProvider =
    NotifierProvider<ModerationController, ModerationState>(
      ModerationController.new,
    );
