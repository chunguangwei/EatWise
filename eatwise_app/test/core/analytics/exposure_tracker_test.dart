import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 录制型假通道：收集上报批次。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> sent = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    sent.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

AnalyticsService _buildService(_RecordingClient client) {
  return AnalyticsService(
    consentStore: InMemoryConsentStore(analyticsGranted: true),
    queueStore: InMemoryEventQueueStore(),
    context: AnalyticsContext(
      deviceIdentityStore: InMemoryDeviceIdentityStore(),
    ),
    clients: <AnalyticsClient>[client],
  );
}

/// 可视区 800×600 下构造指定顶部偏移的 200px 高被追踪块。
Widget _app(
  AnalyticsService service, {
  required double topSpacer,
  required String dedupeKey,
  ScrollController? controller,
}) {
  return ProviderScope(
    overrides: <Override>[analyticsServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: <Widget>[
            SizedBox(height: topSpacer),
            ExposureTracker(
              eventName: 'test_expose',
              dedupeKey: dedupeKey,
              properties: <String, Object?>{'ck': dedupeKey},
              child: Container(height: 200, color: Colors.red),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    // 测试环境即时分发可视回调（生产默认 500ms 聚合）。
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('ExposureTracker 可视判定（§4.1）', () {
    testWidgets('可见比例 49%：持续超 500ms 不上报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      // 200px 块顶部偏移 502 → 可见 98px = 49%。
      await tester.pumpWidget(_app(service, topSpacer: 502, dedupeKey: 'k1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await service.flush();

      expect(client.sent, isEmpty);
    });

    testWidgets('可见比例 50%：持续 500ms 上报一次', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      // 顶部偏移 500 → 可见 100px = 50%（边界达标）。
      await tester.pumpWidget(_app(service, topSpacer: 500, dedupeKey: 'k1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();

      expect(client.sent.map((e) => e.name), <String>['test_expose']);
      expect(client.sent.single.properties['ck'], 'k1');
    });

    testWidgets('持续 499ms 不上报，满 500ms 上报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(_app(service, topSpacer: 0, dedupeKey: 'k1'));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 499));
      await service.flush();
      expect(client.sent, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await service.flush();
      expect(client.sent, hasLength(1));
    });

    testWidgets('滚出再滚入：session 内不重复上报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(service, topSpacer: 0, dedupeKey: 'k1', controller: scroll),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();
      expect(client.sent, hasLength(1));

      // 滚出视口再滚回：去重键不变，session 内不重复计。
      scroll.jumpTo(400);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();
      expect(client.sent, hasLength(1));
    });

    testWidgets('组件重建（Tab 往返模拟）：同去重键不重复上报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(_app(service, topSpacer: 0, dedupeKey: 'k1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // 整棵子树重建（如 Tab 切走切回）：同 session 同键只报一次。
      await tester.pumpWidget(_app(service, topSpacer: 0, dedupeKey: 'k1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();
      expect(client.sent, hasLength(1));
    });

    testWidgets('contentKey 变化：按新内容重计一次', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(_app(service, topSpacer: 0, dedupeKey: 'post_a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // postId 变化 → 新内容重计（§4.1 列表类曝光）。
      await tester.pumpWidget(_app(service, topSpacer: 0, dedupeKey: 'post_b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();

      expect(client.sent, hasLength(2));
      expect(client.sent.map((e) => e.properties['ck']), <Object?>[
        'post_a',
        'post_b',
      ]);
    });

    testWidgets('达标前滚出：计时取消，重新进入后重新计满 500ms', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(service, topSpacer: 0, dedupeKey: 'k1', controller: scroll),
      );
      await tester.pump();
      // 停留 300ms 后滚出：不足 500ms 不计。
      await tester.pump(const Duration(milliseconds: 300));
      scroll.jumpTo(400);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();
      expect(client.sent, isEmpty);

      // 滚回重新计时，计满 500ms 后上报。
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await service.flush();
      expect(client.sent, hasLength(1));
    });
  });
}
