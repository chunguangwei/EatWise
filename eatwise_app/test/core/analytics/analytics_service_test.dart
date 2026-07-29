import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 录制型假通道：记录每批上报与 suppressed 标记。
final class FakeAnalyticsClient implements AnalyticsClient {
  final List<List<AnalyticsEvent>> batches = <List<AnalyticsEvent>>[];
  final List<String> suppressed = <String>[];

  /// 注入失败：'transient' / 'permanent' / null。
  String? failWith;

  List<AnalyticsEvent> get allSent =>
      batches.expand((b) => b).toList(growable: false);

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    if (failWith == 'permanent') {
      throw const AnalyticsPermanentException(400);
    }
    if (failWith == 'transient') {
      throw StateError('network down');
    }
    batches.add(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {
    suppressed.add(name);
  }
}

AnalyticsService buildService({
  ConsentStore? consentStore,
  EventQueueStore? queueStore,
  List<AnalyticsClient>? clients,
  DateTime Function()? now,
  int flushThreshold = 20,
  Duration flushInterval = const Duration(seconds: 30),
}) {
  return AnalyticsService(
    consentStore: consentStore ?? InMemoryConsentStore(analyticsGranted: true),
    queueStore: queueStore ?? InMemoryEventQueueStore(),
    context: AnalyticsContext(
      deviceIdentityStore: InMemoryDeviceIdentityStore(),
    ),
    clients: clients ?? const <AnalyticsClient>[],
    flushThreshold: flushThreshold,
    flushInterval: flushInterval,
    now: now,
  );
}

/// 等未 await 的内部 flush 落定后再补一次 flush（测试断言前统一调用）。
Future<void> settle(AnalyticsService service) async {
  await Future<void>.delayed(Duration.zero);
  await service.flush();
}

void main() {
  group('授权门禁（D-18 / §1.6）', () {
    test('未授权时 track 为 no-op：丢弃不缓存，标注 suppressed', () async {
      final client = FakeAnalyticsClient();
      final queue = InMemoryEventQueueStore();
      final service = buildService(
        consentStore: InMemoryConsentStore(),
        queueStore: queue,
        clients: <AnalyticsClient>[client],
      );
      service.track('app_open', properties: const {'launch_type': 'cold'});
      service.track('record_flow_success');
      await service.flush();

      expect(client.allSent, isEmpty);
      expect(client.suppressed, <String>['app_open', 'record_flow_success']);
      expect(service.queueLength, 0);
      expect(queue.events, isEmpty); // 从严：授权前不落缓存（§1.3 假设 2）
    });

    test('授权后事件正常采集与上报', () async {
      final client = FakeAnalyticsClient();
      final consent = InMemoryConsentStore();
      final service = buildService(
        consentStore: consent,
        clients: <AnalyticsClient>[client],
      );
      await service.setAnalyticsConsent(true, consentType: 'initial_dialog');
      await service.flush();

      final names = client.allSent.map((e) => e.name).toList();
      expect(names, contains('privacy_consent_change'));
      final consentEvent = client.allSent.firstWhere(
        (e) => e.name == 'privacy_consent_change',
      );
      expect(consentEvent.properties['granted'], isTrue);
      expect(consentEvent.properties['consent_type'], 'initial_dialog');

      service.track('fasting_ring_expose');
      await settle(service);
      expect(
        client.allSent.map((e) => e.name),
        contains('fasting_ring_expose'),
      );
    });

    test('撤回即时生效：先上报「关闭」一次，随后清空队列停采（§1.6-2）', () async {
      final client = FakeAnalyticsClient();
      final consent = InMemoryConsentStore(analyticsGranted: true);
      final service = buildService(
        consentStore: consent,
        clients: <AnalyticsClient>[client],
      );
      service.track('fasting_extend_click');
      await service.setAnalyticsConsent(false);

      // 撤回事件已尽力上报，且此后队列清空、track 为 no-op。
      final revoke = client.allSent.firstWhere(
        (e) => e.name == 'privacy_consent_change',
      );
      expect(revoke.properties['granted'], isFalse);
      expect(service.queueLength, 0);

      final sentBefore = client.allSent.length;
      service.track('fasting_ring_expose');
      await service.flush();
      expect(client.allSent.length, sentBefore);
      expect(client.suppressed, contains('fasting_ring_expose'));
    });
  });

  group('批量与离线（§1.5）', () {
    test('达到 20 条阈值自动 flush', () async {
      final client = FakeAnalyticsClient();
      final service = buildService(clients: <AnalyticsClient>[client]);
      for (var i = 0; i < 19; i++) {
        service.track('fasting_ring_expose');
      }
      await Future<void>.delayed(Duration.zero);
      expect(client.allSent, isEmpty);
      service.track('fasting_ring_expose'); // 第 20 条触发
      await Future<void>.delayed(Duration.zero);
      expect(client.allSent.length, 20);
      expect(service.queueLength, 0);
    });

    test('定时 flush：30 秒间隔到点发批', () async {
      final client = FakeAnalyticsClient();
      final service = buildService(
        clients: <AnalyticsClient>[client],
        flushInterval: const Duration(milliseconds: 50),
      );
      service.start();
      service.track('app_open', properties: const {'launch_type': 'cold'});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(client.allSent.length, 1);
      await service.dispose();
    });

    test('flushNow 关键转化事件不等批量立即上报', () async {
      final client = FakeAnalyticsClient();
      final service = buildService(clients: <AnalyticsClient>[client]);
      service.track('record_flow_success', flushNow: true);
      await Future<void>.delayed(Duration.zero);
      expect(client.allSent.single.name, 'record_flow_success');
    });

    test('批量包按 timestamp 升序（离线回补不扭曲漏斗）', () async {
      final client = FakeAnalyticsClient();
      var now = DateTime.utc(2026, 7, 27, 12);
      final service = buildService(
        clients: <AnalyticsClient>[client],
        now: () => now,
      );
      service.track('fasting_end_click');
      now = now.subtract(const Duration(minutes: 5)); // 时钟回拨乱序
      service.track('fasting_end_confirm');
      await service.flush();
      final timestamps = client.allSent.map((e) => e.timestamp).toList();
      final sorted = List<int>.of(timestamps)..sort();
      expect(timestamps, orderedEquals(sorted));
    });

    test('上报失败保留队列重试；恢复后全部送达（服务端 event_id 幂等）', () async {
      final client = FakeAnalyticsClient()..failWith = 'transient';
      final queue = InMemoryEventQueueStore();
      final service = buildService(
        clients: <AnalyticsClient>[client],
        queueStore: queue,
      );
      service.track('record_flow_success');
      await service.flush();
      expect(client.allSent, isEmpty);
      expect(service.queueLength, 1);
      expect(queue.events.length, 1); // 已持久化，进程被杀不丢

      client.failWith = null;
      await service.flush();
      expect(client.allSent.single.name, 'record_flow_success');
      expect(service.queueLength, 0);
    });

    test('4xx 丢弃该批并记 app_track_error', () async {
      final client = FakeAnalyticsClient()..failWith = 'permanent';
      final service = buildService(clients: <AnalyticsClient>[client]);
      service.track('onboard_skip_click');
      await service.flush();
      expect(service.queueLength, greaterThanOrEqualTo(0));
      expect(client.allSent, isEmpty); // 4xx 批被丢弃

      client.failWith = null;
      await service.flush();
      final errorEvent = client.allSent.firstWhere(
        (e) => e.name == 'app_track_error',
      );
      expect(errorEvent.properties['error_code'], 400);
      expect(errorEvent.properties['dropped_count'], 1);
    });

    test('启动重放：遗留队列恢复后随 flush 发出', () async {
      final queue = InMemoryEventQueueStore();
      final seed = buildService(queueStore: queue)..track('app_open');
      await seed.dispose(); // 持久化一条遗留事件

      final client = FakeAnalyticsClient();
      final service = buildService(
        queueStore: queue,
        clients: <AnalyticsClient>[client],
      );
      expect(service.queueLength, 1);
      await service.flush();
      expect(client.allSent.single.name, 'app_open');
    });
  });

  group('曝光去重（§4.1）与记录耗时事件对（§2.5）', () {
    test('同一 session 内同一去重键只上报一次；内容键变化重计', () async {
      final client = FakeAnalyticsClient();
      final service = buildService(clients: <AnalyticsClient>[client]);
      service.trackExpose(
        'fasting_ring_expose',
        dedupeKey: 'home:ring:fasting',
      );
      service.trackExpose(
        'fasting_ring_expose',
        dedupeKey: 'home:ring:fasting',
      );
      service.trackExpose('fasting_ring_expose', dedupeKey: 'home:ring:eating');
      await service.flush();
      expect(client.allSent.length, 2);
    });

    test('record_flow_start → success 配对：duration_ms 由客户端打点', () async {
      var now = DateTime.utc(2026, 7, 27, 12);
      final client = FakeAnalyticsClient();
      final service = buildService(
        clients: <AnalyticsClient>[client],
        now: () => now,
      );
      final flowId = service.startRecordFlow();
      service.updateRecordFlowEntry(flowId, 'camera');
      now = now.add(const Duration(milliseconds: 12400));
      final flow = service.endRecordFlow(flowId);
      service.track(
        'record_flow_success',
        properties: <String, Object?>{
          'flow_id': flowId,
          'duration_ms': flow!.durationMs,
          'entry_type': flow.entryType,
        },
      );
      await service.flush();

      final start = client.allSent.firstWhere(
        (e) => e.name == 'record_flow_start',
      );
      final success = client.allSent.firstWhere(
        (e) => e.name == 'record_flow_success',
      );
      expect(start.properties['flow_id'], flowId);
      expect(success.properties['flow_id'], flowId);
      expect(success.properties['duration_ms'], 12400);
      expect(success.properties['entry_type'], 'camera');
      // 同 flow_id 配对（验收 §5.2 事件对完整性）。
      expect(start.properties['flow_id'], success.properties['flow_id']);
    });

    test('后台超过 30 秒回前台：轮换 session 并记 app_open warm', () async {
      var now = DateTime.utc(2026, 7, 27, 12);
      final client = FakeAnalyticsClient();
      final service = buildService(
        clients: <AnalyticsClient>[client],
        now: () => now,
      );
      service.trackExpose(
        'fasting_ring_expose',
        dedupeKey: 'home:ring:fasting',
      );
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 31));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // 新 session：曝光去重键重置，允许再次计。
      service.trackExpose(
        'fasting_ring_expose',
        dedupeKey: 'home:ring:fasting',
      );
      await service.flush();
      final names = client.allSent.map((e) => e.name).toList();
      expect(names, contains('app_open'));
      expect(names.where((n) => n == 'fasting_ring_expose').length, 2);
      final warm = client.allSent.firstWhere((e) => e.name == 'app_open');
      expect(warm.properties['launch_type'], 'warm');
    });
  });
}
