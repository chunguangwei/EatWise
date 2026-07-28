import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'social_test_fakes.dart';

/// 打卡流控制器：四态 / 游标分页 / 点赞乐观更新 / 发布乐观更新与回滚 / 举报。
void main() {
  late FakeSocialApi api;
  late ProviderContainer container;

  FeedController controller() =>
      container.read(feedControllerProvider.notifier);
  FeedState state() => container.read(feedControllerProvider);

  /// 等首屏 refresh 完成。
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    api = FakeSocialApi();
    container = ProviderContainer(
      overrides: <Override>[socialApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
  });

  test('首屏加载成功：ready + 顺序保持 + 游标', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1'), stubPost(id: 'p2')];
    controller(); // 触发 build
    await settle();
    expect(state().status, FeedStatus.ready);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p1', 'p2']);
    expect(state().hasMore, isFalse);
    expect(state().nextCursor, isNull);
  });

  test('首屏加载失败：error + 服务端本地化 message；refresh 可恢复', () async {
    api.feedError = networkException;
    controller();
    await settle();
    expect(state().status, FeedStatus.error);
    expect(state().errorMessage, isNotEmpty);

    api.feedError = null;
    api.posts = <ServerPost>[stubPost(id: 'p1')];
    await controller().refresh();
    expect(state().status, FeedStatus.ready);
    expect(state().items, hasLength(1));
  });

  test('空打卡流：ready 且 items 为空（空态引导由 UI 呈现）', () async {
    controller();
    await settle();
    expect(state().status, FeedStatus.ready);
    expect(state().items, isEmpty);
  });

  test('游标分页：loadMore 追加、到底后不再请求、失败保留已有', () async {
    api.posts = List<ServerPost>.generate(
      FeedController.pageSize + 5,
      (i) => stubPost(id: 'p$i'),
    );
    controller();
    await settle();
    expect(state().items, hasLength(FeedController.pageSize));
    expect(state().hasMore, isTrue);

    await controller().loadMore();
    expect(state().items, hasLength(FeedController.pageSize + 5));
    expect(state().hasMore, isFalse);
    final calls = api.fetchFeedCalls;

    await controller().loadMore(); // 到底 → 不再请求
    expect(api.fetchFeedCalls, calls);
  });

  test('点赞：乐观 +1 后以服务端权威计数收敛；再点取消', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1', likeCount: 4)];
    controller();
    await settle();

    final before = state().items.first.post;
    final future = controller().toggleLike('p1');
    // 乐观更新立即生效（不等网络）
    expect(state().items.first.post.likeCount, before.likeCount + 1);
    expect(state().items.first.post.likedByMe, isTrue);
    await future;
    expect(api.liked, <String>['p1']);
    expect(state().items.first.post.likeCount, 5);

    await controller().toggleLike('p1');
    expect(api.unliked, <String>['p1']);
    expect(state().items.first.post.likedByMe, isFalse);
    expect(state().items.first.post.likeCount, 4);
  });

  test('点赞失败回滚原状', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1', likeCount: 4)];
    api.likeError = networkException;
    controller();
    await settle();

    await controller().toggleLike('p1');
    expect(state().items.first.post.likeCount, 4);
    expect(state().items.first.post.likedByMe, isFalse);
  });

  test('发布成功：pending 卡置顶，随后替换为服务端卡', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1')];
    controller();
    await settle();

    final future = controller().publish(text: '第 3 天！', streakDays: 3);
    // 乐观：pending 卡已在流顶
    expect(state().items.first.pendingSync, isTrue);
    expect(state().items.first.post.text, '第 3 天！');
    final result = await future;
    expect(result, isA<PublishOk>());
    expect(state().items.first.pendingSync, isFalse);
    expect(state().items.first.post.id, 'srv-1');
    expect(state().items.first.post.isAuthor, isTrue);
    expect(state().items, hasLength(2));
  });

  test('发布被审核拒绝：回滚移除 + 返回双语拒绝原因', () async {
    api.createError = rejectedException;
    controller();
    await settle();

    final result = await controller().publish(text: '违规内容');
    expect(result, isA<PublishRejected>());
    expect((result as PublishRejected).message, '内容未通过审核，无法发布');
    expect(state().items, isEmpty);
  });

  test('发布网络失败：回滚移除 + PublishFailed', () async {
    api.createError = networkException;
    controller();
    await settle();

    final result = await controller().publish(text: '离线内容');
    expect(result, isA<PublishFailed>());
    expect(state().items, isEmpty);
  });

  test('举报：成功移除该帖；失败恢复原位', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1'), stubPost(id: 'p2')];
    controller();
    await settle();

    final ok = await controller().report('p1');
    expect(ok, isTrue);
    expect(api.reported, <String>['p1']);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2']);

    api.reportError = networkException;
    final failed = await controller().report('p2');
    expect(failed, isFalse);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2']);
  });
}
