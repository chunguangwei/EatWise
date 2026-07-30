import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/presentation/community_feed_page.dart';
import 'package:eatwise/features/social/presentation/compose_page.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'social_test_fakes.dart';

/// 社区打卡流 widget 测试：四态 / 点赞 UI / 举报流程 / 双语 / 截断展开。
void main() {
  final fixedNow = DateTime.utc(2026, 7, 28, 13);

  late FakeSocialApi api;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    // 组件级曝光埋点（ExposureTracker）：即时分发可视回调，避免插件默认
    // 500ms 聚合 Timer 在卸载时未决。
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    api = FakeSocialApi();
  });

  List<Override> overrides() => <Override>[
    socialApiProvider.overrideWithValue(api),
    socialNowProvider.overrideWithValue(() => fixedNow),
    streakApiProvider.overrideWithValue(FakeStreakApi()),
  ];

  GoRouter router() => GoRouter(
    initialLocation: '/community',
    routes: <RouteBase>[
      GoRoute(
        path: '/community',
        builder: (context, state) => const CommunityFeedPage(),
      ),
      GoRoute(
        path: '/community/compose',
        builder: (context, state) => const ComposePage(),
      ),
    ],
  );

  Future<void> pumpFeed(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: overrides(),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('加载中骨架 → 空态引导发布（文案 + CTA + FAB）', (tester) async {
    await pumpFeed(tester);
    expect(find.text('这里在等今天第一口美食登场。'), findsOneWidget);
    expect(find.text('发布打卡'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('成功流：昵称/相对时间/连续天数徽章/点赞计数/举报入口', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', text: '第 7 天，完成！', streakDaysAtPost: 7, likeCount: 4),
      // 本人 pending 帖：审核中标记（D-17 先审后发）
      stubPost(
        id: 'p2',
        text: '我的待审帖',
        isAuthor: true,
        auditStatus: 'pending',
        streakDaysAtPost: null,
      ),
    ];
    await pumpFeed(tester);

    expect(find.text('小林'), findsNWidgets(2));
    expect(find.text('连续 7 天'), findsOneWidget); // streak 徽章（D-12）
    expect(find.text('1 小时前'), findsWidgets); // 相对时间
    expect(find.text('4'), findsOneWidget); // 点赞计数
    expect(find.text('内容审核中，仅自己可见'), findsOneWidget);
    // 举报入口仅他人帖有（p2 是本人帖）
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('streak 为 0 或空不显示「0 天连胜」徽章（四态规范 4.2）', (tester) async {
    api.posts = <ServerPost>[
      stubPost(id: 'p1', streakDaysAtPost: 0),
      stubPost(id: 'p2', streakDaysAtPost: null),
    ];
    await pumpFeed(tester);
    expect(find.textContaining('0 天'), findsNothing);
    await unmount(tester);
  });

  testWidgets('点赞按钮：点击 +1 再点 -1（乐观更新 UI）', (tester) async {
    api.posts = <ServerPost>[stubPost(id: 'p1', likeCount: 4)];
    await pumpFeed(tester);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('举报流程：确认对话框 → 卡片移除 + 提示', (tester) async {
    api.posts = <ServerPost>[stubPost(id: 'p1', text: '被举报的内容')];
    await pumpFeed(tester);

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定举报这条打卡吗'), findsOneWidget);

    await tester.tap(find.text('举报').last);
    await tester.pumpAndSettle();
    expect(api.reported, <String>['p1']);
    expect(find.text('被举报的内容'), findsNothing);
    expect(find.text('已举报，感谢反馈'), findsOneWidget);
    // 流空 → 空态引导
    expect(find.text('这里在等今天第一口美食登场。'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('错误态：错误文案 + 重试按钮恢复', (tester) async {
    api.feedError = networkException;
    await pumpFeed(tester);
    expect(find.text('打卡流加载失败，请稍后重试'), findsOneWidget);

    api.feedError = null;
    api.posts = <ServerPost>[stubPost(id: 'p1')];
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('打卡内容'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('超长文本 3 行截断 + 「展开」可点开（四态规范 4.1）', (tester) async {
    api.posts = <ServerPost>[stubPost(id: 'p1', text: '这是一段很长很长的打卡文字，' * 20)];
    await pumpFeed(tester);

    expect(find.text('展开'), findsOneWidget);
    await tester.tap(find.text('展开'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
    expect(tester.takeException(), isNull); // 展开后无溢出错
    await unmount(tester);
  });

  testWidgets('下拉刷新触发重新拉取', (tester) async {
    api.posts = <ServerPost>[stubPost(id: 'p1')];
    await pumpFeed(tester);
    final calls = api.fetchFeedCalls;

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(api.fetchFeedCalls, greaterThan(calls));
    await unmount(tester);
  });

  testWidgets('英文渲染：空态与 CTA 双语（D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpFeed(tester);
    expect(
      find.text("Waiting for today's first check-in to show up."),
      findsOneWidget,
    );
    expect(find.text('Check in'), findsOneWidget);
    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  testWidgets('FAB 进入发布页，发布成功后新卡置顶', (tester) async {
    api.posts = <ServerPost>[stubPost(id: 'p1')];
    await pumpFeed(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('发布打卡'), findsOneWidget); // AppBar 标题

    await tester.enterText(find.byType(TextField), '今天也完成了 16:8！');
    await tester.tap(find.text('发布'));
    await tester.pump();
    // 乐观：pending 卡先入流（发布页已 pop 回流页）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('今天也完成了 16:8！'), findsOneWidget);
    expect(find.text('连续 3 天'), findsOneWidget); // 服务端权威 streak 徽章
    await unmount(tester);
  });
}
