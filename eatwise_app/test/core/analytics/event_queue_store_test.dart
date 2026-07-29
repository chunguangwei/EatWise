import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  AnalyticsEvent event(String name, int timestamp) => AnalyticsEvent(
    eventId: 'e-$name-$timestamp',
    name: name,
    timestamp: timestamp,
    clientDate: '2026-07-27',
    common: const <String, Object?>{'platform': 'android'},
    properties: const <String, Object?>{'k': 'v'},
  );

  group('SharedPreferencesEventQueueStore 离线缓存（§1.5）', () {
    test('JSON 持久化往返：进程重启后可恢复', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesEventQueueStore(prefs);
      await store.save(<AnalyticsEvent>[
        event('app_open', 1),
        event('record_flow_success', 2),
      ]);

      // 模拟重启：同一 prefs 新建 store 读回。
      final reopened = SharedPreferencesEventQueueStore(prefs);
      final restored = reopened.load();
      expect(restored.length, 2);
      expect(restored.first.name, 'app_open');
      expect(restored.last.name, 'record_flow_success');
      expect(restored.last.properties, <String, Object?>{'k': 'v'});
    });

    test('损坏数据不拖垮读取（防御）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesEventQueueStore.queueKey: 'not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesEventQueueStore(prefs);
      expect(store.load(), isEmpty);
    });

    test('超上限按 FIFO 丢弃并累计 dropped 计数（app_track_drop）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesEventQueueStore(prefs);
      final events = <AnalyticsEvent>[
        for (var i = 0; i < SharedPreferencesEventQueueStore.maxEvents + 5; i++)
          event('app_open', i),
      ];
      await store.save(events);
      final restored = store.load();
      expect(restored.length, SharedPreferencesEventQueueStore.maxEvents);
      expect(restored.first.timestamp, 5); // 最早 5 条被 FIFO 丢弃
      expect(store.consumeDroppedCount(), 5);
      expect(store.consumeDroppedCount(), 0); // 已消费清零
    });
  });
}
