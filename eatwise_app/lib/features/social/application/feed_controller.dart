import 'dart:async';

import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/data/upload_api.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show newClientRequestId;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 打卡流四态（《规格-全局 UI 四态》§3.2.4 社区·打卡流）。
enum FeedStatus {
  /// 首屏加载中（骨架 = 3 张打卡卡占位）。
  loading,

  /// 加载失败（错误页 + 重试）。
  error,

  /// 就绪（成功 / 空态由 items 是否为空区分）。
  ready,
}

/// 流条目：ServerPost + 本地乐观标记。
final class FeedItem {
  const FeedItem({required this.post, this.pendingSync = false});

  final ServerPost post;

  /// 乐观发布的待确认卡（先审后发上传中）；成功后被服务端视图替换，
  /// 失败回滚移除（§3.2.4 乐观更新 + 失败回滚）。
  final bool pendingSync;

  FeedItem copyWith({ServerPost? post, bool? pendingSync}) {
    return FeedItem(
      post: post ?? this.post,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}

final class FeedState {
  const FeedState({
    required this.status,
    this.items = const <FeedItem>[],
    this.hasMore = false,
    this.nextCursor,
    this.loadingMore = false,
    this.errorMessage,
  });

  final FeedStatus status;
  final List<FeedItem> items;
  final bool hasMore;
  final String? nextCursor;
  final bool loadingMore;

  /// 错误态说明（服务端本地化 message，可直接上屏）。
  final String? errorMessage;

  FeedState copyWith({
    FeedStatus? status,
    List<FeedItem>? items,
    bool? hasMore,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FeedState(
      status: status ?? this.status,
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 发布结果（发布页据此前进/提示）。
sealed class PublishResult {
  const PublishResult();
}

final class PublishOk extends PublishResult {
  const PublishOk(this.post);

  final ServerPost post;
}

final class PublishRejected extends PublishResult {
  const PublishRejected(this.message);

  /// 服务端双语拒绝原因（POST_CONTENT_REJECTED，可直接上屏）。
  final String message;
}

final class PublishFailed extends PublishResult {
  const PublishFailed();
}

/// 社区接口 Provider（测试 override 为桩实现）。
final socialApiProvider = Provider<SocialApi>((ref) {
  return SocialApi(ref.watch(apiDioProvider));
});

/// 图片上传接口 Provider（测试 override 为桩实现）。
final uploadApiProvider = Provider<UploadApi>((ref) {
  return UploadApi(ref.watch(apiDioProvider));
});

/// 打卡流控制器（M5 P1：游标分页 / 下拉刷新 / 点赞乐观更新 /
/// 发布乐观更新 + 失败回滚）。
final class FeedController extends Notifier<FeedState> {
  static const int pageSize = 20;

  SocialApi get _api => ref.read(socialApiProvider);

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  FeedState build() {
    unawaited(refresh());
    return const FeedState(status: FeedStatus.loading);
  }

  /// 首屏加载 / 下拉刷新（重置游标）。
  Future<void> refresh() async {
    try {
      final page = await _api.fetchFeed(limit: pageSize);
      state = FeedState(
        status: FeedStatus.ready,
        items: page.items.map((p) => FeedItem(post: p)).toList(),
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } on ApiException catch (e) {
      state = FeedState(status: FeedStatus.error, errorMessage: e.message);
    }
  }

  /// 加载更多（游标分页；滚动到底触发）。
  Future<void> loadMore() async {
    if (state.status != FeedStatus.ready ||
        !state.hasMore ||
        state.loadingMore ||
        state.nextCursor == null) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _api.fetchFeed(
        limit: pageSize,
        cursor: state.nextCursor,
      );
      final known = state.items.map((i) => i.post.id).toSet();
      state = state.copyWith(
        items: <FeedItem>[
          ...state.items,
          ...page.items
              .where((p) => !known.contains(p.id))
              .map((p) => FeedItem(post: p)),
        ],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } on ApiException {
      // 翻页失败保留已有内容，下次滚动到底可重试。
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 点赞/取消点赞（乐观更新，失败回滚；幂等由服务端 postId+userId 保证）。
  ///
  /// 回写一律按 postId 重新定位（[_replaceById]）：等待网络期间
  /// refresh/loadMore/publish 可能改序或移除条目，位置索引会写错帖子。
  Future<void> toggleLike(String postId) async {
    final index = state.items.indexWhere((i) => i.post.id == postId);
    if (index < 0) return;
    final item = state.items[index];
    if (item.pendingSync) return; // 待确认卡不可互动
    final liked = item.post.likedByMe;
    // 轻互动埋点（§3.5 community_interaction；post_id 哈希不含内容 §1.6-4）。
    _analytics.track(
      'community_interaction',
      properties: <String, Object?>{
        'action': liked ? 'unlike' : 'like',
        'post_id_hash': anonymizedContentId(postId),
        'is_own_post': item.post.isAuthor,
      },
    );
    final optimistic = item.post.copyWith(
      likedByMe: !liked,
      likeCount: item.post.likeCount + (liked ? -1 : 1),
    );
    _replaceById(postId, FeedItem(post: optimistic));
    try {
      final result = liked
          ? await _api.unlike(postId)
          : await _api.like(postId);
      _replaceById(
        postId,
        FeedItem(
          post: optimistic.copyWith(
            likeCount: result.likeCount,
            likedByMe: result.likedByMe,
          ),
        ),
      );
    } on ApiException {
      _replaceById(postId, item); // 回滚（帖子已不在流中则丢弃）
    }
  }

  /// 发布打卡（乐观更新：pending 卡先入流顶部；成功替换为服务端视图，
  /// 失败回滚移除）。streak 天数由服务端权威写入（D-12），此处仅展示入参。
  Future<PublishResult> publish({
    required String text,
    List<String> imageUrls = const <String>[],
    int? streakDays,
    bool anonymous = false,
    int? avatarId,
  }) async {
    final trimmed = text.trim();
    final localId = 'local-${newClientRequestId()}';
    final optimistic = FeedItem(
      pendingSync: true,
      post: ServerPost(
        id: localId,
        text: trimmed,
        imageUrls: imageUrls,
        streakDaysAtPost: streakDays,
        likeCount: 0,
        likedByMe: false,
        auditStatus: 'pending',
        isAuthor: true,
        authorNickname: null,
        anonymous: anonymous,
        avatarId: avatarId,
        createdAtUtc: DateTime.now().toUtc(),
      ),
    );
    state = state.copyWith(
      status: FeedStatus.ready,
      items: <FeedItem>[optimistic, ...state.items],
    );
    try {
      final created = await _api.createPost(
        clientRequestId: newClientRequestId(),
        text: trimmed,
        imageUrls: imageUrls,
        anonymous: anonymous,
        avatarId: avatarId,
      );
      _replaceById(localId, FeedItem(post: created));
      // 打卡发布埋点（§3.5 community_post_publish；2.6 活跃判定）。
      _analytics.track(
        'community_post_publish',
        properties: <String, Object?>{
          'has_image': imageUrls.isNotEmpty,
          'streak_days': created.streakDaysAtPost ?? streakDays ?? 0,
          // 〔假设〕服务端 auditStatus 'pending' → 字典枚举 'review'。
          'audit_result': created.auditStatus == 'approved'
              ? 'pass'
              : created.auditStatus == 'rejected'
              ? 'reject'
              : 'review',
        },
      );
      return PublishOk(created);
    } on BusinessApiException catch (e) {
      _removeById(localId);
      if (e.code == 'POST_CONTENT_REJECTED') {
        return PublishRejected(e.message);
      }
      return const PublishFailed();
    } on ApiException {
      _removeById(localId);
      return const PublishFailed();
    }
  }

  /// 举报（服务端下架转人工；本地乐观移除该帖）。
  ///
  /// 失败回滚锚定「原后继」postId 重新定位插入点：等待网络期间
  /// refresh/loadMore 可能改序，位置索引会插错位置；期间被 refresh
  /// 拉回的帖子不重复插入。
  Future<bool> report(String postId) async {
    final index = state.items.indexWhere((i) => i.post.id == postId);
    if (index < 0) return false;
    final removed = state.items[index];
    final nextId = index + 1 < state.items.length
        ? state.items[index + 1].post.id
        : null;
    _removeById(postId);
    try {
      await _api.report(postId);
      return true;
    } on ApiException {
      if (state.items.any((i) => i.post.id == postId)) return false;
      final anchor = nextId == null
          ? state.items.length
          : state.items.indexWhere((i) => i.post.id == nextId);
      // 原后继也被移除（refresh 整体换掉）时退化为追加到末尾。
      final at = anchor < 0 ? state.items.length : anchor;
      state = state.copyWith(
        items: <FeedItem>[
          ...state.items.sublist(0, at),
          removed,
          ...state.items.sublist(at),
        ],
      );
      return false;
    }
  }

  /// 删除本人帖子（服务端软删幂等；本地乐观移除 + 失败回滚）。
  ///
  /// 回滚锚定「原后继」postId 重新定位插入点（与 [report] 同款：等待网络
  /// 期间 refresh/loadMore 可能改序，位置索引会插错位置）。
  Future<bool> delete(String postId) async {
    final index = state.items.indexWhere((i) => i.post.id == postId);
    if (index < 0) return false;
    final removed = state.items[index];
    final nextId = index + 1 < state.items.length
        ? state.items[index + 1].post.id
        : null;
    _removeById(postId);
    try {
      await _api.deletePost(postId);
      return true;
    } on ApiException {
      if (state.items.any((i) => i.post.id == postId)) return false;
      final anchor = nextId == null
          ? state.items.length
          : state.items.indexWhere((i) => i.post.id == nextId);
      final at = anchor < 0 ? state.items.length : anchor;
      state = state.copyWith(
        items: <FeedItem>[
          ...state.items.sublist(0, at),
          removed,
          ...state.items.sublist(at),
        ],
      );
      return false;
    }
  }

  /// 按 postId 重定位替换（找不到说明条目已被移除/刷新，丢弃本次回写）。
  void _replaceById(String postId, FeedItem item) {
    final index = state.items.indexWhere((i) => i.post.id == postId);
    if (index < 0) return;
    final items = List<FeedItem>.of(state.items);
    items[index] = item;
    state = state.copyWith(items: items);
  }

  void _removeById(String postId) {
    state = state.copyWith(
      items: state.items.where((i) => i.post.id != postId).toList(),
    );
  }
}

/// 打卡流 Provider。
final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

/// 当前时间（卡片相对时间渲染用；测试 override 注入固定时间）。
final socialNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
