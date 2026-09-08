import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 默认滚动深度档位（§4.2 主流口径 25/50/75/100）。
const List<int> kScrollDepthThresholds = <int>[25, 50, 75, 100];

/// 滚动深度采集容器（事件 `scroll_depth`；§4.2 口径以**最大**滚动深度为准，
/// 故只报历史最大档位：回滚不回落、每档位一个会话内只报一次）。
///
/// 落地方式：不接管各页自建的 [ScrollController]，用 [NotificationListener]
/// 监听冒泡的滚动通知，直接从 `ScrollMetrics` 算深度
/// `pixels / maxScrollExtent`；回调恒返回 false，只观测不消费。
///
/// 规则：
/// - **不跳档**：深度向下取整后逐档判定，40% 只报 25；一次拖到 90% 补报
///   25/50/75（每档仍只报一次）；上报值是**档位**（25/50/75/100），不是
///   实时百分比，保证 `depth_percent` 落在字典 0–100 档位枚举内；
/// - **短内容**：`maxScrollExtent <= 0`（不足一屏、无法滚动）等同整页可见，
///   即深度 100，与「一次拖到底」同口径四档齐报，短页不会拿不到深度；
/// - **轴隔离**：只统计 [scrollDirection]（默认纵向）主滚动，页内横滑卡片/
///   轮播不污染页面深度；`depth > 0`（通知已冒泡穿过一层视口，即来自内层
///   嵌套 Scrollable）同样忽略，深度只归属本容器包住的主体滚动区；
/// - **去重**：页面级（[componentId] 为空）走 `AnalyticsService.trackExpose`，
///   去重键 `scroll_depth:<page_id>:<档位>`，session 内同档位只报一次（Tab
///   切走切回、页面重建不重复计，session 轮换由采集层清空去重集，§4.1）；
///   组件级只按容器实例去重（随页面销毁重建可重计），不占用 session 去重集。
class ScrollDepthTracker extends ConsumerStatefulWidget {
  const ScrollDepthTracker({
    required this.page,
    required this.child,
    this.componentId,
    this.thresholds = kScrollDepthThresholds,
    this.scrollDirection = Axis.vertical,
    super.key,
  });

  /// 字典 `page_id`（附录 B：`home` / `analytics` / `analytics_reports` 等，
  /// 与 `page_stay` 同源；页面级事件另作 `page` 属性上报）。
  final String page;

  /// 组件标识（可空）：非空即组件级深度，随事件 `component_id` 上报。
  final String? componentId;

  /// 上报档位（百分比）。
  final List<int> thresholds;

  /// 统计的滚动方向（页面主体方向）。
  final Axis scrollDirection;

  final Widget child;

  @override
  ConsumerState<ScrollDepthTracker> createState() => _ScrollDepthTrackerState();
}

class _ScrollDepthTrackerState extends ConsumerState<ScrollDepthTracker> {
  /// 本容器已报档位（容器生命周期内每档位只报一次；页面级另有 session 去重）。
  final Set<int> _reached = <int>{};

  @override
  void didUpdateWidget(covariant ScrollDepthTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 页面/组件键变化（同位置换成另一页另一组件）→ 档位重新计。
    if (oldWidget.page != widget.page ||
        oldWidget.componentId != widget.componentId) {
      _reached.clear();
    }
  }

  /// 用户滚动（ScrollUpdate/End 等都带最新 metrics）。
  bool _onScroll(ScrollNotification notification) {
    return _evaluate(notification.metrics, notification.depth);
  }

  /// 布局后的度量变化（内容高度/视口变化）：短内容不滚动也要拿到深度。
  bool _onMetrics(ScrollMetricsNotification notification) {
    return _evaluate(notification.metrics, notification.depth);
  }

  bool _evaluate(ScrollMetrics metrics, int depth) {
    if (metrics.axis != widget.scrollDirection) return false;
    // 只认本页主体滚动（depth>0 为内层嵌套 Scrollable 冒泡，另由内层容器计）。
    if (depth != 0) return false;

    // 不足一屏：无法滚动即整页可见，按 100 收口。
    final percent = metrics.maxScrollExtent <= 0
        ? 100
        : (metrics.pixels / metrics.maxScrollExtent * 100).floor();
    if (percent <= 0) return false;
    // 不跳档：一次跨多档（快甩/程序化滚到底）逐档补报，各档仍只报一次。
    for (final threshold in widget.thresholds) {
      if (percent >= threshold) _report(threshold);
    }
    return false;
  }

  void _report(int threshold) {
    if (!_reached.add(threshold)) return;
    final analytics = ref.read(analyticsServiceProvider);
    final properties = <String, Object?>{
      'page': widget.page,
      'depth_percent': threshold,
      if (widget.componentId != null) 'component_id': widget.componentId,
    };
    if (widget.componentId == null) {
      // 页面级：session 内同档位只报一次（§4.1 去重键同源约定）。
      analytics.trackExpose(
        'scroll_depth',
        dedupeKey: 'scroll_depth:${widget.page}:$threshold',
        properties: properties,
      );
    } else {
      analytics.track('scroll_depth', properties: properties);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
    );
  }
}
