import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/analytics/page_stay_tracker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 录制型假通道。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> sent = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    sent.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

Route<dynamic> _route() => PageRouteBuilder<void>(
  pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
);

void main() {
  late _RecordingClient client;
  late AnalyticsService service;
  late DateTime now;
  late String location;
  late PageStayTracker tracker;

  setUp(() {
    client = _RecordingClient();
    now = DateTime.utc(2026, 7, 28, 8);
    location = '/';
    service = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[client],
      now: () => now,
    );
    tracker = PageStayTracker(analytics: service, now: () => now)
      ..locationResolver = () => location;
  });

  List<AnalyticsEvent> pageStays() =>
      client.sent.where((e) => e.name == 'page_stay').toList();

  group('pageIdForLocation（§4.2 page_id 枚举/附录 B）', () {
    test('一级页映射', () {
      expect(pageIdForLocation('/'), 'home');
      expect(pageIdForLocation('/record'), 'record');
      expect(pageIdForLocation('/data'), 'analytics');
      expect(pageIdForLocation('/community'), 'community');
      expect(pageIdForLocation('/profile'), 'profile');
    });

    test('二级页按路径段 snake 拼接', () {
      expect(pageIdForLocation('/data/reports'), 'analytics_reports');
      expect(pageIdForLocation('/community/compose'), 'community_compose');
      expect(
        pageIdForLocation('/onboarding/recommendation'),
        'onboarding_recommendation',
      );
    });
  });

  group('PageStayTracker 分段计时（§4.2）', () {
    test('push：上一页按 navigate 结算并携带停留时长', () async {
      tracker.didPush(_route(), null); // 进入 home
      now = now.add(const Duration(seconds: 2));
      location = '/record';
      tracker.didPush(_route(), _route());
      await service.flush();

      final stays = pageStays();
      expect(stays, hasLength(1));
      expect(stays.single.properties, <String, Object?>{
        'page_id': 'home',
        'stay_ms': 2000,
        'end_reason': 'navigate',
      });
      expect(tracker.currentPageId, 'record');
    });

    test('pop：被弹页按 navigate 结算，回到上一页重新计时', () async {
      tracker.didPush(_route(), null); // home
      now = now.add(const Duration(seconds: 2));
      location = '/record';
      tracker.didPush(_route(), _route()); // record
      now = now.add(const Duration(seconds: 3));
      location = '/';
      tracker.didPop(_route(), _route());
      await service.flush();

      final stays = pageStays();
      expect(stays, hasLength(2));
      expect(stays[0].properties['page_id'], 'home');
      expect(stays[1].properties, <String, Object?>{
        'page_id': 'record',
        'stay_ms': 3000,
        'end_reason': 'navigate',
      });
      expect(tracker.currentPageId, 'home');
    });

    test('Tab 切换：end_reason=tab_switch；同页重按不上报', () async {
      tracker.didPush(_route(), null); // home
      now = now.add(const Duration(seconds: 5));
      tracker.onTabSwitch('analytics');
      tracker.onTabSwitch('analytics'); // 同页 no-op
      await service.flush();

      final stays = pageStays();
      expect(stays, hasLength(1));
      expect(stays.single.properties, <String, Object?>{
        'page_id': 'home',
        'stay_ms': 5000,
        'end_reason': 'tab_switch',
      });
      expect(tracker.currentPageId, 'analytics');
    });

    test('退后台按 background 结算，回前台同 session 新开一段', () async {
      tracker.didPush(_route(), null); // home
      now = now.add(const Duration(seconds: 4));
      tracker.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.flush();

      var stays = pageStays();
      expect(stays.single.properties, <String, Object?>{
        'page_id': 'home',
        'stay_ms': 4000,
        'end_reason': 'background',
      });

      // 回前台：同页新开一段，后续离开只计新段时长。
      now = now.add(const Duration(minutes: 1));
      tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(seconds: 6));
      tracker.onTabSwitch('record');
      await service.flush();

      stays = pageStays();
      expect(stays, hasLength(2));
      expect(stays[1].properties, <String, Object?>{
        'page_id': 'home',
        'stay_ms': 6000,
        'end_reason': 'tab_switch',
      });
    });
  });
}
