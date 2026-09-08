import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 我的贡献列表四态（《全局 UI 四态》口径同社区打卡流）。
enum ContributionsStatus { loading, ready, error }

/// 我的贡献列表状态（页码分页累积 + 状态过滤）。
final class ContributionsState {
  const ContributionsState({
    this.status = ContributionsStatus.loading,
    this.filter,
    this.items = const <FoodContribution>[],
    this.total = 0,
    this.page = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.errorMessage,
  });

  /// 加载态。
  final ContributionsStatus status;

  /// 当前状态过滤（null = 全部）。
  final FoodContributionStatus? filter;

  /// 已加载条目（服务端 createdAt 降序，跨页累积）。
  final List<FoodContribution> items;

  /// 符合条件的总条数。
  final int total;

  /// 已加载到的页码（0 = 尚未加载）。
  final int page;

  /// 是否还有下一页。
  final bool hasMore;

  /// 翻页进行中（底部指示器）。
  final bool loadingMore;

  /// 错误信息（首屏失败时展示）。
  final String? errorMessage;

  ContributionsState copyWith({
    ContributionsStatus? status,
    List<FoodContribution>? items,
    int? total,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContributionsState(
      status: status ?? this.status,
      filter: filter,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 我的贡献控制器（GET /foods/contributions：状态过滤 + 页码分页 + 下拉刷新）。
final class ContributionsController extends Notifier<ContributionsState> {
  static const int pageSize = 20;

  CustomFoodRemote get _remote => ref.read(customFoodRemoteProvider);

  @override
  ContributionsState build() {
    // 首屏加载（build 内不可读 state，过滤条件必为缺省「全部」）。
    unawaited(_loadFirstPage(null));
    return const ContributionsState();
  }

  /// 切换状态过滤（重新从第 1 页加载）。
  Future<void> setFilter(FoodContributionStatus? filter) async {
    if (state.filter == filter) return;
    state = ContributionsState(
      status: ContributionsStatus.loading,
      filter: filter,
    );
    await _loadFirstPage(filter);
  }

  /// 下拉刷新（保留当前过滤，重置到第 1 页）。
  Future<void> refresh() => _loadFirstPage(state.filter);

  /// 滚动到底加载下一页（页码分页；失败保留已有内容可重试）。
  Future<void> loadMore() async {
    if (state.status != ContributionsStatus.ready ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    final next = state.page + 1;
    try {
      final result = await _remote.getContributions(
        status: state.filter,
        page: next,
        pageSize: pageSize,
      );
      final known = state.items.map((c) => c.id).toSet();
      state = state.copyWith(
        items: <FoodContribution>[
          ...state.items,
          ...result.items.where((c) => !known.contains(c.id)),
        ],
        total: result.total,
        page: next,
        hasMore: result.hasMore,
        loadingMore: false,
      );
    } on ApiException {
      state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> _loadFirstPage(FoodContributionStatus? filter) async {
    try {
      final result = await _remote.getContributions(
        status: filter,
        page: 1,
        pageSize: pageSize,
      );
      state = ContributionsState(
        status: ContributionsStatus.ready,
        filter: filter,
        items: result.items,
        total: result.total,
        page: 1,
        hasMore: result.hasMore,
      );
    } on ApiException catch (e) {
      state = ContributionsState(
        status: ContributionsStatus.error,
        filter: filter,
        errorMessage: e.message,
      );
    }
  }
}

/// 我的贡献列表 Provider。
final NotifierProvider<ContributionsController, ContributionsState>
contributionsControllerProvider =
    NotifierProvider<ContributionsController, ContributionsState>(
      ContributionsController.new,
    );
