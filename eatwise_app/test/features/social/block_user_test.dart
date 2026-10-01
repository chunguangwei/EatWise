import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/presentation/blocked_users_page.dart';
import 'package:eatwise/features/social/presentation/community_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'social_test_fakes.dart';

/// UGC 屏蔽用户（App Store 条例 1.2）widget 测试：
/// 帖卡屏蔽链路 / 匿名帖无屏蔽入口 / 屏蔽失败回滚 / 已屏蔽用户页。
void main() {
  final fixedNow = DateTime.utc(2026, 7, 28, 13);

  late FakeSocialApi api;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    api = FakeSocialApi();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpFeed(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            socialApiProvider.overrideWithValue(api),
            socialNowProvider.overrideWithValue(() => fixedNow),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: GoRouter(
              initialLocation: '/community',
              routes: <RouteBase>[
                GoRoute(
                  path: '/community',
                  builder: (context, state) => const CommunityFeedPage(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpBlockedUsers(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[socialApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const BlockedUsersPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('屏蔽链路：确认弹窗 → POST → 卡片移除 + 提示', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', text: '骚扰内容', nickname: '扰民', authorId: 'u-spam'),
      stubPost(id: 'p2', text: '正常打卡', authorId: 'u-normal'),
    ];
    await pumpFeed(tester);
    expect(find.byIcon(Icons.block_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.block_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('屏蔽后将不再看到'), findsOneWidget);

    await tester.tap(find.text('屏蔽该用户'));
    await tester.pumpAndSettle();
    expect(api.blockedCalls, <String>['u-spam']);
    expect(find.text('骚扰内容'), findsNothing); // 该作者帖即时移除
    expect(find.text('正常打卡'), findsOneWidget); // 其他作者不受影响
    expect(find.text('已屏蔽，不再显示 TA 的内容'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('取消屏蔽确认：不发请求，卡片保留', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', text: '骚扰内容', authorId: 'u-spam'),
    ];
    await pumpFeed(tester);

    await tester.tap(find.byIcon(Icons.block_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.blockedCalls, isEmpty);
    expect(find.text('骚扰内容'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('匿名帖无屏蔽入口（作者身份已抹除）；本人帖也无', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', anonymous: true, authorId: null, nickname: null),
      stubPost(id: 'p2', isAuthor: true),
    ];
    await pumpFeed(tester);
    expect(find.byIcon(Icons.block_rounded), findsNothing);
    await unmount(tester);
  });

  testWidgets('屏蔽失败：refresh 拉回帖子 + 失败提示', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', text: '骚扰内容', authorId: 'u-spam'),
    ];
    await pumpFeed(tester);

    api.blockError = networkException;
    await tester.tap(find.byIcon(Icons.block_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏蔽该用户'));
    await tester.pumpAndSettle();
    expect(find.text('屏蔽失败，请稍后重试'), findsOneWidget);
    expect(find.text('骚扰内容'), findsOneWidget); // 回滚：刷新拉回
    await unmount(tester);
  });

  testWidgets('已屏蔽用户页：列表 + 解除屏蔽链路', (tester) async {
    api.blockedUsers = <BlockedUser>[
      const BlockedUser(userId: 'u-spam', nickname: '扰民'),
      const BlockedUser(userId: 'u-ad', nickname: null), // 昵称缺失兜底
    ];
    await pumpBlockedUsers(tester);
    expect(find.text('扰民'), findsOneWidget);
    expect(find.text('EatWise 伙伴'), findsOneWidget);

    await tester.tap(find.text('解除屏蔽').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('解除屏蔽后'), findsOneWidget);

    await tester.tap(find.text('解除屏蔽').last);
    await tester.pumpAndSettle();
    expect(api.unblockedCalls, <String>['u-spam']);
    expect(find.text('已解除屏蔽'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('已屏蔽用户页：空态与错误态重试', (tester) async {
    await pumpBlockedUsers(tester);
    expect(find.textContaining('暂无屏蔽的用户'), findsOneWidget);
    await unmount(tester);

    api.blockedUsersError = networkException;
    await pumpBlockedUsers(tester);
    expect(find.text('列表加载失败，请稍后重试'), findsOneWidget);
    api.blockedUsersError = null;
    api.blockedUsers = <BlockedUser>[
      const BlockedUser(userId: 'u-spam', nickname: '扰民'),
    ];
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('扰民'), findsOneWidget);
    await unmount(tester);
  });
}
