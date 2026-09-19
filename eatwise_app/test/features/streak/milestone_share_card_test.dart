import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/streak/presentation/milestone_badge.dart';
import 'package:eatwise/features/streak/presentation/milestone_share_card.dart';
import 'package:eatwise/features/streak/presentation/milestone_share_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录型上报通道（捕获 flush 的事件批）。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    events.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

/// 内存分享通道（避免 share_plus / image_gallery_saver 插件依赖）。
final class _FakeShareActions implements ShareCardActions {
  int shareCalls = 0;
  int saveCalls = 0;
  String? lastFileName;
  Uint8List? lastPng;
  bool saveResult = true;

  @override
  Future<void> shareSystem(Uint8List png, String fileName) async {
    shareCalls++;
    lastFileName = fileName;
    lastPng = png;
  }

  @override
  Future<bool> saveToAlbum(Uint8List png, String fileName) async {
    saveCalls++;
    lastFileName = fileName;
    lastPng = png;
    return saveResult;
  }
}

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Widget wrap(Widget child) {
    return TranslationProvider(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  AnalyticsService analyticsWith(_RecordingClient client) {
    return AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
        userIdResolver: () => null,
      ),
      clients: <AnalyticsClient>[client],
    );
  }

  MilestoneShareCard cardOf({int days = 7}) {
    final zh = AppLocale.zhCn.buildSync();
    final en = AppLocale.en.buildSync();
    return MilestoneShareCard(
      days: days,
      date: '2026-07-30',
      primaryTitle: zh.streak.milestone.title(days: '$days'),
      secondaryTitle: en.streak.milestone.title(days: '$days'),
      daysUnit: '天',
      appName: '明食 EatWise',
      tagline: '轻盈断食，自在生活',
    );
  }

  /// 卡片为 1080×1350 固定设计稿，测试表面（800×600）内需经 FittedBox
  /// 等比缩放泵入（与分享预览页的真实用法一致；布局尺寸不变）。
  Widget previewOf(Widget card) {
    return wrap(SizedBox(width: 300, child: FittedBox(child: card)));
  }

  group('分享图卡渲染（语义）', () {
    testWidgets('大数字天数 + 中英双语文案 + 日期 + App 名', (tester) async {
      await tester.pumpWidget(previewOf(cardOf()));
      // 大数字连胜天数。
      expect(find.text('7'), findsOneWidget);
      expect(find.text('天'), findsOneWidget);
      // 中英双语里程碑文案（自我鼓励口径，无虚假分位）。
      expect(find.text('连续 7 天！这个节奏太稳了，继续保持 🎉'), findsOneWidget);
      expect(
        find.text('7-day streak! What a steady rhythm — keep it up 🎉'),
        findsOneWidget,
      );
      // 日期 + App 名 + 口号。
      expect(find.text('2026-07-30'), findsOneWidget);
      expect(find.text('明食 EatWise'), findsOneWidget);
      expect(find.text('轻盈断食，自在生活'), findsOneWidget);
    });

    testWidgets('设计尺寸 1080×1350（4:5）', (tester) async {
      await tester.pumpWidget(previewOf(cardOf(days: 30)));
      final size = tester.getSize(find.byType(MilestoneShareCard));
      expect(size.width, MilestoneShareCard.designWidth);
      expect(size.height, MilestoneShareCard.designHeight);
      expect(size.width / size.height, closeTo(4 / 5, 1e-6));
      expect(find.text('30'), findsOneWidget);
    });
  });

  group('PNG 导出（纯渲染函数）', () {
    testWidgets('导出字节非空且为 PNG，宽度恒为 1080', (tester) async {
      final key = GlobalKey();
      // 预览缩放场景（FittedBox 内 1080 逻辑尺寸），导出仍恒为 1080 宽。
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 300,
            child: FittedBox(
              fit: BoxFit.contain,
              child: RepaintBoundary(key: key, child: cardOf()),
            ),
          ),
        ),
      );
      final png = await tester.runAsync(() => captureShareCardPng(key));
      expect(png, isNotNull);
      expect(png!.length, greaterThan(1000));
      // PNG 魔数。
      expect(png.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
      // IHDR 宽度（字节 16–19，大端）= 1080。
      final width = ByteData.sublistView(png, 16, 20).getUint32(0);
      final height = ByteData.sublistView(png, 20, 24).getUint32(0);
      expect(width, 1080);
      expect(height, 1350);
    });
  });

  group('分享预览页（交互 + 埋点）', () {
    testWidgets('展示：预览 + 双按钮 + share_card_expose 埋点', (tester) async {
      final client = _RecordingClient();
      final analytics = analyticsWith(client);
      addTearDown(analytics.dispose);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 560,
            child: MilestoneShareSheet(
              days: 7,
              analytics: analytics,
              actions: _FakeShareActions(),
              date: '2026-07-30',
            ),
          ),
        ),
      );
      expect(find.text('点亮成就 · 分享图卡'), findsOneWidget);
      expect(find.byType(MilestoneShareCard), findsOneWidget);
      expect(find.text('保存到相册'), findsOneWidget);
      expect(find.text('系统分享'), findsOneWidget);
      await analytics.flush();
      final expose = client.events
          .where((e) => e.name == 'share_card_expose')
          .toList();
      expect(expose, hasLength(1));
      expect(expose.single.properties['share_type'], 'badge');
      expect(expose.single.properties['milestone'], 7);
    });

    testWidgets('保存到相册：share_click + 通道调用 + share_card_saved + 提示', (
      tester,
    ) async {
      final client = _RecordingClient();
      final analytics = analyticsWith(client);
      addTearDown(analytics.dispose);
      final actions = _FakeShareActions();
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 560,
            child: MilestoneShareSheet(
              days: 7,
              analytics: analytics,
              actions: actions,
              date: '2026-07-30',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('保存到相册'));
        // 等导出 + 保存异步链路完成。
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.saveCalls, 1);
      expect(actions.lastFileName, 'eatwise_streak_7d.png');
      expect(actions.lastPng, isNotNull);
      expect(actions.lastPng!.length, greaterThan(1000));
      expect(find.text('已保存到相册'), findsOneWidget);
      await analytics.flush();
      final names = client.events.map((e) => e.name).toList();
      expect(names, contains('share_card_expose'));
      expect(names, contains('share_click'));
      expect(names, contains('share_card_saved'));
      final click = client.events.firstWhere((e) => e.name == 'share_click');
      expect(click.properties['channel'], 'save_image');
      expect(click.properties['milestone'], 7);
    });

    testWidgets('系统分享：share_click(channel=system) + 通道调用', (tester) async {
      final client = _RecordingClient();
      final analytics = analyticsWith(client);
      addTearDown(analytics.dispose);
      final actions = _FakeShareActions();
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 560,
            child: MilestoneShareSheet(
              days: 30,
              analytics: analytics,
              actions: actions,
              date: '2026-07-30',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('系统分享'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(actions.shareCalls, 1);
      expect(actions.lastFileName, 'eatwise_streak_30d.png');
      await analytics.flush();
      final click = client.events.firstWhere((e) => e.name == 'share_click');
      expect(click.properties['channel'], 'system');
      expect(click.properties['milestone'], 30);
      // 系统分享不报 share_card_saved。
      expect(client.events.where((e) => e.name == 'share_card_saved'), isEmpty);
    });

    testWidgets('保存失败：提示失败文案，不报 share_card_saved', (tester) async {
      final client = _RecordingClient();
      final analytics = analyticsWith(client);
      addTearDown(analytics.dispose);
      final actions = _FakeShareActions()..saveResult = false;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 560,
            child: MilestoneShareSheet(
              days: 3,
              analytics: analytics,
              actions: actions,
              date: '2026-07-30',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('保存到相册'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('保存失败'), findsOneWidget);
      await analytics.flush();
      expect(client.events.where((e) => e.name == 'share_card_saved'), isEmpty);
    });
  });

  group('徽章接线（US-5.1 点按分享）', () {
    testWidgets('点按「分享」弹出分享预览页', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: TranslationProvider(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(body: MilestoneBadge(days: 7, onDismiss: () {})),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      expect(find.text('点亮成就 · 分享图卡'), findsOneWidget);
      expect(find.byType(MilestoneShareCard), findsOneWidget);
      expect(find.text('保存到相册'), findsOneWidget);
      expect(find.text('系统分享'), findsOneWidget);
    });
  });
}
