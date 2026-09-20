import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// 打卡帖视图（契约 §3.9：C1 响应 / C2 流条目 / C3 详情同构）。
final class ServerPost {
  const ServerPost({
    required this.id,
    required this.text,
    required this.imageUrls,
    required this.streakDaysAtPost,
    required this.likeCount,
    required this.likedByMe,
    required this.auditStatus,
    required this.isAuthor,
    required this.authorNickname,
    required this.createdAtUtc,
    this.anonymous = false,
    this.avatarId,
  });

  final String id;
  final String text;
  final List<String> imageUrls;

  /// 发布时连续达标天数（服务端权威，D-12 口径；可能为 null）。
  final int? streakDaysAtPost;
  final int likeCount;
  final bool likedByMe;

  /// 审核状态（pending / approved / rejected，先审后发 D-17）。
  final String auditStatus;
  final bool isAuthor;

  /// 作者昵称（可为 null，UI 兜底「EatWise 伙伴」〔假设〕）。
  final String? authorNickname;

  /// 匿名发帖：作者身份对非作者遮蔽（服务端视图已抹除 author）。
  final bool anonymous;

  /// 预设头像库索引（0..7，见 kSocialAvatars）；非匿名帖为 null。
  final int? avatarId;
  final DateTime createdAtUtc;

  ServerPost copyWith({int? likeCount, bool? likedByMe, String? auditStatus}) {
    return ServerPost(
      id: id,
      text: text,
      imageUrls: imageUrls,
      streakDaysAtPost: streakDaysAtPost,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      auditStatus: auditStatus ?? this.auditStatus,
      isAuthor: isAuthor,
      authorNickname: authorNickname,
      anonymous: anonymous,
      avatarId: avatarId,
      createdAtUtc: createdAtUtc,
    );
  }

  factory ServerPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return ServerPost(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      imageUrls: (json['imageUrls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      streakDaysAtPost: (json['streakDaysAtPost'] as num?)?.toInt(),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      auditStatus: json['auditStatus'] as String? ?? 'approved',
      isAuthor: json['isAuthor'] as bool? ?? false,
      authorNickname: author['nickname'] as String?,
      anonymous: json['anonymous'] as bool? ?? false,
      avatarId: (json['avatarId'] as num?)?.toInt(),
      createdAtUtc:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// C2 打卡流分页结果。
final class FeedPage {
  const FeedPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ServerPost> items;
  final String? nextCursor;
  final bool hasMore;
}

/// 社区打卡接口（契约 §3.9，C1/C2/C5/C6/C7）。
class SocialApi {
  SocialApi(this._dio);

  final Dio _dio;

  Future<ServerPost> createPost({
    required String clientRequestId,
    required String text,
    List<String> imageUrls = const <String>[],
    bool anonymous = false,
    int? avatarId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'text': text,
          if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
          if (anonymous) 'anonymous': true,
          if (anonymous && avatarId != null) 'avatarId': avatarId,
        },
      );
      return ServerPost.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// C2 打卡流（游标分页倒序；他人 approved + 本人 pending/approved）。
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/posts/feed',
        queryParameters: <String, dynamic>{'limit': limit, 'cursor': ?cursor},
      );
      final data = response.data ?? const <String, dynamic>{};
      final pageInfo =
          data['pageInfo'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      return FeedPage(
        items: (data['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ServerPost.fromJson)
            .toList(),
        nextCursor: pageInfo['nextCursor'] as String?,
        hasMore: pageInfo['hasMore'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// C5 点赞（幂等，返回权威计数）。
  Future<({int likeCount, bool likedByMe})> like(String postId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/like',
      );
      final data = response.data ?? const <String, dynamic>{};
      return (
        likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: data['likedByMe'] as bool? ?? true,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// C6 取消点赞（幂等，返回权威计数）。
  Future<({int likeCount, bool likedByMe})> unlike(String postId) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/posts/$postId/like',
      );
      final data = response.data ?? const <String, dynamic>{};
      return (
        likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: data['likedByMe'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// C7 举报（幂等；服务端下架并转人工复核）。
  Future<void> report(String postId, {String? reason}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/report',
        data: <String, dynamic>{'reason': ?reason},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// C4 删除本人打卡（服务端软删幂等；非作者 404）。
  Future<void> deletePost(String postId) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/posts/$postId');
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
