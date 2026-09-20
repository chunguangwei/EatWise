import 'dart:async';

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

  test('点赞回写按 postId 重定位：在途 refresh 换序不写错帖子', () async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', likeCount: 1),
      stubPost(id: 'p2', likeCount: 2),
    ];
    controller();
    await settle();

    api.likeGate = Completer<void>();
    final future = controller().toggleLike('p1');
    // 点赞在途时下拉刷新换序（p2 移到前面）。
    api.posts = <ServerPost>[
      stubPost(id: 'p2', likeCount: 2),
      stubPost(id: 'p1', likeCount: 1),
    ];
    await controller().refresh();
    // 刷新以服务端为准（乐观更新被覆盖，顺序换为 p2 在前）。
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2', 'p1']);
    api.likeGate!.complete();
    await future;

    final p1 = state().items.firstWhere((i) => i.post.id == 'p1').post;
    final p2 = state().items.firstWhere((i) => i.post.id == 'p2').post;
    expect(p1.likedByMe, isTrue);
    expect(p1.likeCount, 2); // 服务端权威计数（1+1）
    expect(p2.likeCount, 2); // 未被误写
    expect(p2.likedByMe, isFalse);
  });

  test('点赞完成时帖子已被刷新移除：丢弃回写，不报错', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1'), stubPost(id: 'p2')];
    controller();
    await settle();

    api.likeGate = Completer<void>();
    final future = controller().toggleLike('p1');
    // 点赞在途时 refresh 把 p1 刷掉。
    api.posts = <ServerPost>[stubPost(id: 'p2')];
    await controller().refresh();
    api.likeGate!.complete();
    await future; // 不抛异常、不复活已移除的帖子
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2']);
  });

  test('举报失败回滚锚定原后继：在途列表变长仍插回原位', () async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1'),
      stubPost(id: 'p2'),
      stubPost(id: 'p3'),
    ];
    controller();
    await settle();

    api.reportError = networkException;
    api.reportGate = Completer<void>();
    final future = controller().report('p1');
    // 举报在途时 refresh 拉回新列表（不含被举报帖，尾部新增 p4）。
    api.posts = <ServerPost>[
      stubPost(id: 'p2'),
      stubPost(id: 'p3'),
      stubPost(id: 'p4'),
    ];
    await controller().refresh();
    api.reportGate!.complete();
    final ok = await future;

    expect(ok, isFalse);
    // 插回原后继 p2 之前（原位），而不是按旧索引错位或丢失。
    expect(state().items.map((i) => i.post.id).toList(), <String>[
      'p1',
      'p2',
      'p3',
      'p4',
    ]);
  });

  test('举报失败但期间 refresh 已拉回该帖：不重复插入', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1'), stubPost(id: 'p2')];
    controller();
    await settle();

    api.reportError = networkException;
    api.reportGate = Completer<void>();
    final future = controller().report('p1');
    // 举报在途时 refresh 把 p1 重新拉回流中。
    await controller().refresh();
    api.reportGate!.complete();
    final ok = await future;

    expect(ok, isFalse);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p1', 'p2']);
  });

  test('删除：成功移除该帖；失败恢复原位', () async {
    api.posts = <ServerPost>[stubPost(id: 'p1'), stubPost(id: 'p2')];
    controller();
    await settle();

    final ok = await controller().delete('p1');
    expect(ok, isTrue);
    expect(api.deleted, <String>['p1']);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2']);

    api.deleteError = networkException;
    final failed = await controller().delete('p2');
    expect(failed, isFalse);
    expect(state().items.map((i) => i.post.id).toList(), <String>['p2']);
  });

  test('删除失败回滚锚定原后继：在途列表变长仍插回原位', () async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1'),
      stubPost(id: 'p2'),
      stubPost(id: 'p3'),
    ];
    controller();
    await settle();

    api.deleteError = networkException;
    api.deleteGate = Completer<void>();
    final future = controller().delete('p1');
    // 删除在途时 refresh 拉回新列表（不含被删帖，尾部新增 p4）。
    api.posts = <ServerPost>[
      stubPost(id: 'p2'),
      stubPost(id: 'p3'),
      stubPost(id: 'p4'),
    ];
    await controller().refresh();
    api.deleteGate!.complete();
    final ok = await future;

    expect(ok, isFalse);
    expect(state().items.map((i) => i.post.id).toList(), <String>[
      'p1',
      'p2',
      'p3',
      'p4',
    ]);
  });

  test('发布透传匿名参数：乐观卡与服务端视图均带 anonymous/avatarId', () async {
    controller();
    await settle();

    final future = controller().publish(
      text: '匿名打卡',
      anonymous: true,
      avatarId: 3,
    );
    // 乐观卡立即匿名（发帖人自己也知道是匿名帖）。
    expect(state().items.first.post.anonymous, isTrue);
    expect(state().items.first.post.avatarId, 3);
    final result = await future;
    expect(result, isA<PublishOk>());
    expect(api.lastAnonymous, isTrue);
    expect(api.lastAvatarId, 3);
    expect(state().items.first.post.anonymous, isTrue);
    expect(state().items.first.post.avatarId, 3);
  });
}
