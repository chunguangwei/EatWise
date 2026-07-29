import 'dart:async';

import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:flutter/widgets.dart';

/// 埋点采集服务（《埋点规范与事件字典》§1.3–§1.6 客户端实现）。
///
/// 职责：
/// - **授权门禁（D-18 / §1.6-1）**：未授权时 [track] 为 no-op（事件直接丢弃、
///   不落缓存，从严执行最小化收集；debug 下经 client 标注 suppressed）；
///   授权状态变更即时生效，撤回后清空缓存队列（§1.6-2）。
/// - **公共属性注入**：经 [AnalyticsContext] 统一注入（§1.2）。
/// - **批量与离线（§1.5）**：内存队列 + [EventQueueStore] 持久化；
///   ≥[flushThreshold] 条或每 [flushInterval] flush，先到先发；关键转化事件
///   `flushNow` 立即上报；失败保留重试，4xx 丢弃并记 `app_track_error`；
///   App 启动 [start] 时重放离线队列。
/// - **曝光去重（§4.1）**：session 内按去重键只上报一次（组件级
///   ≥50%+500ms 可视判定留 TODO，当前落地页面级曝光）。
/// - **会话（§1.2）**：退后台 >30 秒回前台轮换 session_id 并记 `app_open`。
final class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService({
    required this.consentStore,
    required this.queueStore,
    required this.context,
    this.clients = const <AnalyticsClient>[],
    this.flushThreshold = 20,
    this.flushInterval = const Duration(seconds: 30),
    this.backgroundThreshold = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    // 启动重放：恢复上次进程遗留队列（§1.5 进程被杀不丢）。
    _queue.addAll(queueStore.load());
  }

  final ConsentStore consentStore;
  final EventQueueStore queueStore;
  final AnalyticsContext context;
  final List<AnalyticsClient> clients;
  final DateTime Function() _now;

  /// 批量阈值（条，§1.5〔假设〕20）。
  final int flushThreshold;

  /// 定时 flush 间隔（§1.5〔假设〕30 秒）。
  final Duration flushInterval;

  /// 后台超过该时长回前台视为新会话（§1.2〔假设〕30 秒）。
  final Duration backgroundThreshold;

  final List<AnalyticsEvent> _queue = <AnalyticsEvent>[];
  final Set<String> _exposedKeys = <String>{};
  final Map<String, _RecordFlow> _recordFlows = <String, _RecordFlow>{};

  Timer? _flushTimer;
  DateTime? _pausedAt;
  bool _flushing = false;
  bool _disposed = false;

  /// 是否已授权采集（授权状态变更即时生效）。
  bool get enabled => consentStore.analyticsGranted;

  /// 当前队列长度（Debug 埋点面板/测试用）。
  int get queueLength => _queue.length;

  /// 启动：定时 flush + 重放离线队列（main() 调用一次）。
  void start() {
    _flushTimer ??= Timer.periodic(flushInterval, (_) => unawaited(flush()));
    unawaited(flush());
  }

  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _persist();
  }

  // ---- 授权门禁（§1.6） ----

  /// 授权/撤回（首次隐私弹窗或设置内「数据分析开关」）。
  ///
  /// 变更本身上报 `privacy_consent_change`（flushNow）：授权时先入队再上报；
  /// 撤回时先尽力上报「关闭」事件一次，随后清空缓存队列并停采（§1.6-2）。
  Future<void> setAnalyticsConsent(
    bool granted, {
    String consentType = 'analytics_toggle',
  }) async {
    if (consentStore.analyticsGranted == granted) return;
    if (granted) {
      await consentStore.setAnalyticsGranted(true);
      track(
        'privacy_consent_change',
        properties: <String, Object?>{
          'consent_type': consentType,
          'granted': true,
        },
        flushNow: true,
      );
    } else {
      track(
        'privacy_consent_change',
        properties: <String, Object?>{
          'consent_type': consentType,
          'granted': false,
        },
      );
      await flush();
      await consentStore.setAnalyticsGranted(false);
      _queue.clear();
      _recordFlows.clear();
      await _persist();
    }
  }

  // ---- 事件采集 ----

  /// 采集事件（未授权时 no-op：直接丢弃不落缓存，debug 标注 suppressed）。
  ///
  /// [flushNow] 用于关键转化事件（§1.5：`record_flow_success` /
  /// `fasting_checkin_success` / `onboard_plan_start` /
  /// `privacy_consent_change`），不等批量立即上报。
  void track(
    String name, {
    Map<String, Object?> properties = const <String, Object?>{},
    bool flushNow = false,
  }) {
    if (!enabled) {
      for (final client in clients) {
        client.logSuppressed(name, properties);
      }
      return;
    }
    final now = _now();
    final clientDate = _clientDateOf(now);
    final AnalyticsEvent event;
    try {
      event = AnalyticsEvent(
        eventId: newAnalyticsEventId(),
        name: name,
        timestamp: now.toUtc().millisecondsSinceEpoch,
        clientDate: clientDate,
        common: context.commonProps(clientDate: clientDate),
        properties: properties,
      );
    } on ArgumentError {
      // 字典外命名/类型：开发期即失败，线上防御性丢弃不上报（§1.4）。
      for (final client in clients) {
        client.logSuppressed(name, properties);
      }
      return;
    }
    _queue.add(event);
    unawaited(_persist());
    if (flushNow || _queue.length >= flushThreshold) {
      unawaited(flush());
    }
  }

  /// 曝光事件（§4.1：同一 session 内同一去重键只上报一次；内容键变化
  /// ——如状态/落区变化——应纳入 [dedupeKey] 以重计）。
  void trackExpose(
    String name, {
    required String dedupeKey,
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    if (!_exposedKeys.add(dedupeKey)) return;
    track(name, properties: properties);
  }

  /// App 启动/回前台事件（全局，2.3/2.6 活跃判定）。
  void trackAppOpen({required String launchType, String source = 'icon'}) {
    track(
      'app_open',
      properties: <String, Object?>{
        'launch_type': launchType,
        'source': source,
      },
    );
  }

  // ---- 记录耗时事件对（§2.5：record_flow_start → record_flow_success） ----

  /// 进入记录页：开启一条记录流程（一条流程一个 `flow_id`）并上报
  /// `record_flow_start`，返回 `flow_id`。
  String startRecordFlow({String entryType = 'manual'}) {
    final flowId = 'f_${newAnalyticsEventId().substring(0, 8)}';
    _recordFlows[flowId] = _RecordFlow(_now(), entryType);
    track(
      'record_flow_start',
      properties: <String, Object?>{'flow_id': flowId, 'entry_type': entryType},
    );
    return flowId;
  }

  /// 流程内切换入口：更新 `entry_type`（不新开 `flow_id`，§3.3）。
  void updateRecordFlowEntry(String flowId, String entryType) {
    _recordFlows[flowId]?.entryType = entryType;
  }

  /// 结束流程：返回 `duration_ms`（客户端打点主口径）与最终 `entry_type`；
  /// 未知 `flow_id` 返回 null。
  ({int durationMs, String entryType})? endRecordFlow(String flowId) {
    final flow = _recordFlows.remove(flowId);
    if (flow == null) return null;
    return (
      durationMs: _now().difference(flow.startedAt).inMilliseconds,
      entryType: flow.entryType,
    );
  }

  /// 流程已耗时（abandon 事件 `elapsed_ms` 用；不关闭流程）。
  int? recordFlowElapsedMs(String flowId) {
    final flow = _recordFlows[flowId];
    if (flow == null) return null;
    return _now().difference(flow.startedAt).inMilliseconds;
  }

  // ---- 批量与离线（§1.5） ----

  /// 立即 flush：批量包按 `timestamp` 升序；全部通道成功才出队；
  /// 4xx 丢弃该批并记 `app_track_error`；其他失败保留重试。
  Future<void> flush() async {
    if (_flushing || _disposed) return;
    if (!enabled || _queue.isEmpty) return;
    _flushing = true;
    try {
      final batch = List<AnalyticsEvent>.of(_queue)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      var allSucceeded = true;
      var permanentFailure = false;
      var permanentCode = 0;
      for (final client in clients) {
        try {
          await client.send(batch);
        } on AnalyticsPermanentException catch (e) {
          allSucceeded = false;
          permanentFailure = true;
          permanentCode = e.statusCode;
        } on Object {
          // 5xx/网络错误：保留队列下次重试（服务端按 event_id 幂等）。
          allSucceeded = false;
        }
      }
      if (allSucceeded || permanentFailure) {
        // 成功出队 / 4xx 按规范丢弃（§1.5）。
        for (final event in batch) {
          _queue.remove(event);
        }
        await _persist();
      }
      if (permanentFailure) {
        track(
          'app_track_error',
          properties: <String, Object?>{
            'error_code': permanentCode,
            'dropped_count': batch.length,
          },
        );
      }
    } finally {
      _flushing = false;
    }
  }

  // ---- 会话（§1.2） ----

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pausedAt ??= _now();
        unawaited(_persist());
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (pausedAt != null &&
            _now().difference(pausedAt) > backgroundThreshold) {
          _rotateSession();
          trackAppOpen(launchType: 'warm');
        }
    }
  }

  void _rotateSession() {
    context.sessionId = AnalyticsContext.newSessionId();
    _exposedKeys.clear();
  }

  Future<void> _persist() => queueStore.save(_queue);

  static String _clientDateOf(DateTime now) {
    final local = now.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

final class _RecordFlow {
  _RecordFlow(this.startedAt, this.entryType);

  final DateTime startedAt;
  String entryType;
}
