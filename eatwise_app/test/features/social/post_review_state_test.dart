import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/presentation/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  ServerPost post({
    String status = 'rejected',
    bool author = true,
    Object? reason,
  }) => ServerPost.fromJson({
    'id': 'reviewed-post',
    'text': 'Today’s meal',
    'auditStatus': status,
    'isAuthor': author,
    'auditReason': reason,
    'createdAt': '2026-10-26T00:00:00Z',
  }).copyWith(likeCount: 2);

  Future<void> pump(
    WidgetTester tester,
    ServerPost post, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PostCard(item: FeedItem(post: post)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('审核状态从待审刷新为未公开，显示作者原因且不保留待审标记', (tester) async {
    await pump(tester, post(status: 'pending'));
    expect(find.text(t.social.feed.pendingBadge), findsOneWidget);
    await pump(
      tester,
      post(
        reason: {'zh': '图片信息需要核实', 'en': 'Image information needs checking'},
      ),
    );
    expect(find.text(t.social.feed.pendingBadge), findsNothing);
    expect(find.text('内容未公开，仅自己可见'), findsOneWidget);
    expect(find.text('图片信息需要核实'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('英文暗色大字显示原因，缺英文时回退另一语言', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pump(
      tester,
      post(
        reason: {
          'zh': '暂时下架',
          'en': 'Temporarily removed after a report, awaiting manual review.',
        },
      ),
      dark: true,
    );
    expect(
      find.text('Not public. Only you can see this post.'),
      findsOneWidget,
    );
    expect(
      find.text('Temporarily removed after a report, awaiting manual review.'),
      findsOneWidget,
    );
    await pump(tester, post(reason: {'zh': '暂时下架', 'en': '  '}), dark: true);
    expect(find.text('暂时下架'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('缺失或异常原因采用中性兜底，非作者不显示审核说明', (tester) async {
    for (final reason in <Object?>[
      null,
      'invalid',
      {'zh': 42, 'en': <Object>[]},
    ]) {
      await pump(tester, post(reason: reason));
      expect(find.text('暂未提供审核说明。'), findsOneWidget);
    }
    await pump(tester, post(author: false, reason: {'zh': '内部审核原因'}));
    expect(find.text('内部审核原因'), findsNothing);
    expect(find.text('内容未公开，仅自己可见'), findsNothing);
    await unmount(tester);
  });
}
