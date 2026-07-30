import 'dart:async';

import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 组件级曝光埋点容器（《埋点规范与事件字典》§4.1 客户端落地）。
///
/// 规则：
/// - **可视判定**：child ≥50% 面积进入视口且持续 ≥500ms 才上报一次
///   （[minFraction] / [dwellTime] 可调，测试可注入计时器工厂）；
/// - **会话内去重**：上报走 `AnalyticsService.trackExpose`，同一 session 内
///   同一 [dedupeKey] 只上报一次；滚出再滚入、Tab 切走切回不重复计
///   （session 轮换由采集层清空去重集，跨会话允许重计）；
/// - **内容变化重计**：[dedupeKey] 变化（如 postId、`nutrient+signal_level`
///   变化）视为新内容：重置计时并按新键重计。
///
/// 去重键约定（§4.1：`event_name + page_id + element_key`）由调用方拼入
/// [dedupeKey]，如 `community:post:h_77aa`。
class ExposureTracker extends ConsumerStatefulWidget {
  const ExposureTracker({
    required this.eventName,
    required this.dedupeKey,
    required this.child,
    this.properties = const <String, Object?>{},
    this.minFraction = 0.5,
    this.dwellTime = const Duration(milliseconds: 500),
    this.timerFactory = Timer.new,
    super.key,
  });

  /// 事件名（字典 `_expose` 后缀事件，§1.1 snake_case）。
  final String eventName;

  /// 去重键（含页面/元素/内容键；session 内由采集层去重）。
  final String dedupeKey;

  /// 事件私有属性（字典第三章）。
  final Map<String, Object?> properties;

  /// 可视面积阈值（§4.1〔假设〕主流口径 0.5）。
  final double minFraction;

  /// 持续可视时长（§4.1〔假设〕500ms）。
  final Duration dwellTime;

  /// 计时器工厂（测试可注入，便于 fakeAsync 控制）。
  final Timer Function(Duration duration, void Function() callback)
  timerFactory;

  final Widget child;

  @override
  ConsumerState<ExposureTracker> createState() => _ExposureTrackerState();
}

class _ExposureTrackerState extends ConsumerState<ExposureTracker> {
  Timer? _dwellTimer;

  @override
  void didUpdateWidget(covariant ExposureTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容键变化 → 新内容重计（§4.1）：取消旧计时，等新一帧可视回调。
    if (oldWidget.dedupeKey != widget.dedupeKey) {
      _dwellTimer?.cancel();
      _dwellTimer = null;
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final visibleEnough = info.visibleFraction >= widget.minFraction;
    if (!visibleEnough) {
      _dwellTimer?.cancel();
      _dwellTimer = null;
      return;
    }
    // 达标计时只起一次；trackExpose 幂等去重，滚出滚入不重复。
    _dwellTimer ??= widget.timerFactory(widget.dwellTime, _report);
  }

  void _report() {
    if (!mounted) return;
    ref
        .read(analyticsServiceProvider)
        .trackExpose(
          widget.eventName,
          dedupeKey: widget.dedupeKey,
          properties: widget.properties,
        );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey<String>('exposure:${widget.dedupeKey}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
