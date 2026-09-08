import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/analytics/scroll_depth_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 录制型假通道：收集实际上报事件（同 exposure_tracker_test 约定）。
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

/// 测试视口 800×600；内容 1600 → maxScrollExtent 1000，
/// 25/50/75/100 档对应偏移 250/500/750/1000（整数百分比，无取整噪声）。
///
/// [generation] 变化即换 key → 容器 State 重建（模拟 Tab 切走切回/组件重建）。
Widget _app(
  AnalyticsService service, {
  required ScrollController controller,
  required int generation,
  String page = 'home',
  String? componentId,
  Axis scrollDirection = Axis.vertical,
  double contentExtent = 1600,
}) {
  final crossExtent = scrollDirection == Axis.vertical ? contentExtent : 4000.0;
  return ProviderScope(
    overrides: <Override>[analyticsServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      home: Scaffold(
        body: ScrollDepthTracker(
          key: ValueKey<int>(generation),
          page: page,
          componentId: componentId,
          child: SizedBox(
            height: scrollDirection == Axis.vertical ? null : 200,
            child: ListView(
              scrollDirection: scrollDirection,
              controller: controller,
              children: <Widget>[
                SizedBox(
                  height: scrollDirection == Axis.vertical ? crossExtent : null,
                  width: scrollDirection == Axis.vertical ? null : crossExtent,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 跳到指定偏移并 flush（jumpTo 同步产出带最新 metrics 的滚动通知）。
Future<void> _scrollTo(
  WidgetTester tester,
  AnalyticsService service,
  ScrollController controller,
  double offset,
) async {
  controller.jumpTo(offset);
  await tester.pump();
  await service.flush();
}

List<Object?> _depths(_RecordingClient client) =>
    client.sent.map((e) => e.properties['depth_percent']).toList();

void main() {
  late ScrollController controller;
  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  group('ScrollDepthTracker 档位上报（§4.2）', () {
    testWidgets('初始不报；25% 报 25；40% 不补报 50', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(service, controller: controller, generation: 0),
      );
      await tester.pump();
      await service.flush();
      expect(client.sent, isEmpty, reason: '0% 不上报');

      await _scrollTo(tester, service, controller, 250);
      expect(_depths(client), <Object?>[25]);

      await _scrollTo(tester, service, controller, 400);
      expect(_depths(client), <Object?>[25], reason: '未跨 50 档不重复不误报');
    });

    testWidgets('一次拖到底：25/50/75/100 各一次；回滚不回落', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(service, controller: controller, generation: 0),
      );
      await tester.pump();

      await _scrollTo(tester, service, controller, 1000);
      expect(_depths(client), <Object?>[25, 50, 75, 100], reason: '跨档补报');
      expect(client.sent.every((e) => e.name == 'scroll_depth'), isTrue);
      expect(client.sent.every((e) => e.properties['page'] == 'home'), isTrue);
      expect(
        client.sent.every((e) => !e.properties.containsKey('component_id')),
        isTrue,
        reason: '页面级不带 component_id',
      );

      await _scrollTo(tester, service, controller, 0);
      await _scrollTo(tester, service, controller, 1000);
      expect(client.sent, hasLength(4), reason: '最大深度口径，档位不重复');
    });

    testWidgets('页面级：容器重建（Tab 往返）同 session 同档位不重复报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(service, controller: controller, generation: 0),
      );
      await tester.pump();
      await _scrollTo(tester, service, controller, 250);
      expect(client.sent, hasLength(1));

      await tester.pumpWidget(
        _app(service, controller: controller, generation: 1),
      );
      await tester.pump();
      await _scrollTo(tester, service, controller, 1000);
      expect(_depths(client), <Object?>[
        25,
        50,
        75,
        100,
      ], reason: '25 档同 session 已报，新容器不重复计');
    });

    testWidgets('短内容不足一屏：等同整页可见，四档全报', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(
          service,
          controller: controller,
          generation: 0,
          contentExtent: 200,
        ),
      );
      await tester.pump();
      await service.flush();

      // 无法滚动 = 深度 100%，与「一次拖到底」同口径四档齐报。
      expect(_depths(client), <Object?>[25, 50, 75, 100]);
    });

    testWidgets('横向滚动不计入纵向深度（页内横滑卡不污染）', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(
          service,
          controller: controller,
          generation: 0,
          scrollDirection: Axis.horizontal,
        ),
      );
      await tester.pump();
      await _scrollTo(tester, service, controller, 2000);

      expect(client.sent, isEmpty);
    });

    testWidgets('组件级：带 component_id；容器重建后同档位可重计', (tester) async {
      final client = _RecordingClient();
      final service = _buildService(client);
      await tester.pumpWidget(
        _app(
          service,
          controller: controller,
          generation: 0,
          page: 'record',
          componentId: 'search_results',
        ),
      );
      await tester.pump();
      await _scrollTo(tester, service, controller, 500);
      expect(client.sent, hasLength(2));
      expect(client.sent.first.properties['page'], 'record');
      expect(client.sent.map((e) => e.properties['component_id']), <Object?>[
        'search_results',
        'search_results',
      ]);
      expect(_depths(client), <Object?>[25, 50]);

      // 组件级不占 session 去重集：组件销毁重建后同档位可重计。
      await tester.pumpWidget(
        _app(
          service,
          controller: controller,
          generation: 1,
          page: 'record',
          componentId: 'search_results',
        ),
      );
      await tester.pump();
      await _scrollTo(tester, service, controller, 250);
      expect(_depths(client), <Object?>[25, 50, 25]);
    });
  });
}
