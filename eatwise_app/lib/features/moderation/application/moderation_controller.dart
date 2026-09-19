import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
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
enum ModerationActionResult { approved, rejected }

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
      state = state.copyWith(
        items: state.items.where((c) => c.id != candidateId).toList(),
        clearActing: true,
      );
      return approve
          ? ModerationActionResult.approved
          : ModerationActionResult.rejected;
    } on Object {
      state = state.copyWith(clearActing: true);
      rethrow;
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
