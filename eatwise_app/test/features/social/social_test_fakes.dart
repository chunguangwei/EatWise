import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/data/upload_api.dart';
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

  /// 最近一次 createPost 上行的图片 URL 列表（校验上传链路接入点）。
  List<String> lastImageUrls = const <String>[];

  @override
  Future<ServerPost> createPost({
    required String clientRequestId,
    required String text,
    List<String> imageUrls = const <String>[],
  }) async {
    createCalls += 1;
    lastImageUrls = imageUrls;
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

/// UploadApi 桩：记录上传字节数，按 [error] 决定成功/失败。
final class FakeUploadApi extends UploadApi {
  FakeUploadApi({this.error, this.url = '/v1/uploads/srv-1.png'})
    : super(Dio(BaseOptions(baseUrl: 'http://stub')));

  /// 抛出的异常（null = 上传成功）；测试中可改写以模拟「先失败后重试」。
  Object? error;

  /// 成功时返回的读取路径（服务端契约：相对路径自带 /v1 前缀）。
  final String url;

  int calls = 0;
  final List<Uint8List> uploaded = <Uint8List>[];

  /// 非 null 时上传挂起在该 Completer 上（测试「上传中」态用）。
  Completer<void>? gate;

  @override
  Future<UploadedImageRef> uploadImage(Uint8List bytes) async {
    calls += 1;
    uploaded.add(bytes);
    final pending = gate;
    if (pending != null) await pending.future;
    if (error != null) throw error!;
    return UploadedImageRef(id: 'srv-1.png', url: url);
  }
}

/// 拍照/相册桩：[bytes] 为 null 模拟用户取消。
final class FakePhotoPicker implements PhotoPickerGateway {
  const FakePhotoPicker(this.bytes);

  final Uint8List? bytes;

  @override
  Future<Uint8List?> pick(PhotoSource source) async => bytes;
}

/// 1x1 PNG（本地预览渲染需要合法图片字节）。
final Uint8List pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xfc, 0xff, 0x9f, 0xa1, //
  0x1e, 0x00, 0x07, 0x82, 0x02, 0x7f, 0x3d, 0xc8, 0x48, 0xef, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82, //
]);

/// 常用异常。
const rejectedException = BusinessApiException(
  httpStatus: 400,
  code: 'POST_CONTENT_REJECTED',
  message: '内容未通过审核，无法发布',
);

const networkException = NetworkApiException();

/// 上传超限（服务端 413 UPLOAD_FILE_TOO_LARGE 的本地化 message）。
const tooLargeException = BusinessApiException(
  httpStatus: 413,
  code: 'UPLOAD_FILE_TOO_LARGE',
  message: '图片超过 5MB，请换一张或压缩后再传',
);
