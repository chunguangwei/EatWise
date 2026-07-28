import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';

/// 测试桩打卡（默认他人 approved 帖）。
ServerPost stubPost({
  required String id,
  String text = '打卡内容',
  String? nickname = '小林',
  int? streakDaysAtPost = 7,
  int likeCount = 0,
  bool likedByMe = false,
  String auditStatus = 'approved',
  bool isAuthor = false,
  DateTime? createdAtUtc,
}) {
  return ServerPost(
    id: id,
    text: text,
    imageUrls: const <String>[],
    streakDaysAtPost: streakDaysAtPost,
    likeCount: likeCount,
    likedByMe: likedByMe,
    auditStatus: auditStatus,
    isAuthor: isAuthor,
    authorNickname: nickname,
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 7, 28, 12),
  );
}

/// SocialApi 内存桩：游标 = 起始下标（字符串），模拟服务端分页/点赞/举报。
final class FakeSocialApi extends SocialApi {
  FakeSocialApi() : super(Dio(BaseOptions(baseUrl: 'http://stub')));

  /// 流数据（新→旧）。
  List<ServerPost> posts = <ServerPost>[];

  Object? feedError;
  Object? createError;
  Object? likeError;
  Object? reportError;

  int fetchFeedCalls = 0;
  int createCalls = 0;
  final List<String> liked = <String>[];
  final List<String> unliked = <String>[];
  final List<String> reported = <String>[];

  /// 点赞计数（postId → count）。
  final Map<String, int> likeCounts = <String, int>{};

  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async {
    fetchFeedCalls += 1;
    if (feedError != null) throw feedError!;
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final page = posts.skip(offset).take(limit).toList();
    final next = offset + limit;
    return FeedPage(
      items: page,
      nextCursor: next < posts.length ? '$next' : null,
      hasMore: next < posts.length,
    );
  }

  @override
  Future<ServerPost> createPost({
    required String clientRequestId,
    required String text,
    List<String> imageUrls = const <String>[],
  }) async {
    createCalls += 1;
    if (createError != null) throw createError!;
    return stubPost(
      id: 'srv-$createCalls',
      text: text,
      nickname: '我',
      streakDaysAtPost: 3,
      auditStatus: 'approved',
      isAuthor: true,
    );
  }

  /// 帖子初始点赞数（like/unlike 的权威基数）。
  int _baseCount(String postId) {
    for (final p in posts) {
      if (p.id == postId) return p.likeCount;
    }
    return 0;
  }

  @override
  Future<({int likeCount, bool likedByMe})> like(String postId) async {
    if (likeError != null) throw likeError!;
    liked.add(postId);
    final count = (likeCounts[postId] ?? _baseCount(postId)) + 1;
    likeCounts[postId] = count;
    return (likeCount: count, likedByMe: true);
  }

  @override
  Future<({int likeCount, bool likedByMe})> unlike(String postId) async {
    if (likeError != null) throw likeError!;
    unliked.add(postId);
    final count = (likeCounts[postId] ?? _baseCount(postId)) - 1;
    likeCounts[postId] = count;
    return (likeCount: count, likedByMe: false);
  }

  @override
  Future<void> report(String postId, {String? reason}) async {
    if (reportError != null) throw reportError!;
    reported.add(postId);
  }
}

/// StreakApi 桩（compose 页 streak 徽章数据源；避免真实网络）。
final class FakeStreakApi extends StreakApi {
  FakeStreakApi({this.view, this.error})
    : super(Dio(BaseOptions(baseUrl: 'http://stub')));

  final ServerStreakView? view;
  final Object? error;

  @override
  Future<ServerStreakView> fetchStreak() {
    if (error != null) return Future.error(error!);
    return Future.value(
      view ??
          const ServerStreakView(
            currentStreak: 0,
            longestStreak: 0,
            lastQualifiedDate: null,
            mendCardStock: 2,
            mendCardGrantsThisMonth: 2,
            mendCardExpiresAt: '2026-07-31',
            mendCardUsableWindowDays: 7,
            mendCardStatus: 'available',
          ),
    );
  }

  @override
  Future<List<ServerMilestone>> fetchMilestones() =>
      Future.value(const <ServerMilestone>[]);
}

/// 常用异常。
const rejectedException = BusinessApiException(
  httpStatus: 400,
  code: 'POST_CONTENT_REJECTED',
  message: '内容未通过审核，无法发布',
);

const networkException = NetworkApiException();
