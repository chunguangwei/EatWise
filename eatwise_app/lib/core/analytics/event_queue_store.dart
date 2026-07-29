import 'dart:convert';

import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 埋点事件离线队列持久化（《埋点规范》§1.5：先入队再上报，进程被杀不丢；
/// 失败保留重试）。
abstract interface class EventQueueStore {
  /// 载入上次进程遗留的待上报事件（App 启动重放）。
  List<AnalyticsEvent> load();

  /// 全量覆盖保存当前队列。
  Future<void> save(List<AnalyticsEvent> events);
}

/// SharedPreferences JSON 实现。
///
/// 〔假设〕规范首选 drift 加密表（§1.5），本迭代按任务约定用
/// SharedPreferences JSON；容量上限取 2000 条（SharedPreferences 体积现实约束，
/// 低于规范 10 万条），超出按 FIFO 丢弃并累计丢弃数供 `app_track_drop` 上报。
final class SharedPreferencesEventQueueStore implements EventQueueStore {
  SharedPreferencesEventQueueStore(this._prefs);

  static const String queueKey = 'analytics.event_queue.v1';
  static const String droppedKey = 'analytics.event_queue.dropped';

  /// 队列上限（FIFO 丢弃）。
  static const int maxEvents = 2000;

  final SharedPreferences _prefs;

  @override
  List<AnalyticsEvent> load() {
    final raw = _prefs.getString(queueKey);
    if (raw == null || raw.isEmpty) return const <AnalyticsEvent>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final events = <AnalyticsEvent>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        try {
          events.add(AnalyticsEvent.fromJson(item));
        } on Object {
          // 单条损坏不拖垮整队。
        }
      }
      return events;
    } on Object {
      return const <AnalyticsEvent>[];
    }
  }

  /// 上次保存时被 FIFO 丢弃的事件数（供 `app_track_drop` 上报后清零）。
  int consumeDroppedCount() {
    final dropped = _prefs.getInt(droppedKey) ?? 0;
    if (dropped > 0) _prefs.remove(droppedKey);
    return dropped;
  }

  @override
  Future<void> save(List<AnalyticsEvent> events) async {
    var kept = events;
    if (events.length > maxEvents) {
      final dropped = events.length - maxEvents;
      await _prefs.setInt(
        droppedKey,
        (_prefs.getInt(droppedKey) ?? 0) + dropped,
      );
      kept = events.sublist(dropped);
    }
    await _prefs.setString(queueKey, jsonEncode(kept));
  }
}

/// 内存实现（测试 / 降级场景）。
final class InMemoryEventQueueStore implements EventQueueStore {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  List<AnalyticsEvent> load() => List<AnalyticsEvent>.of(events);

  @override
  Future<void> save(List<AnalyticsEvent> events) async {
    this.events
      ..clear()
      ..addAll(events);
  }
}
