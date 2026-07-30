import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:flutter/widgets.dart';

/// 路由位置 → 字典 page_id（§4.2：一级页 home/record/analytics/community/
/// profile；二级页见附录 B，按路径段 snake 拼接）。
String pageIdForLocation(String location) {
  return switch (location) {
    '/' => 'home',
    '/record' => 'record',
    '/data' => 'analytics',
    '/community' => 'community',
    '/profile' => 'profile',
    // 二级页（附录 B）：归并到所属一级模块前缀。
    '/data/reports' => 'analytics_reports',
    '/community/compose' => 'community_compose',
    _ =>
      location
          .replaceAll(RegExp('^/+'), '')
          .replaceAll('/', '_')
          .replaceAll('-', '_'),
  };
}

/// 页面停留时长采集（《埋点规范与事件字典》§4.2 客户端落地）。
///
/// 以路由层 push/pop 为准（Flutter RouteObserver，与原生生命周期解耦，
/// 双端行为一致）：进入页面开始计时，离开（navigate/tab_switch）或退后台
/// （background）结算一段并上报 `page_stay`（page_id/stay_ms/end_reason）；
/// 退后台回前台构成同 session 时新开一段。Tab 切换走 [onTabSwitch]
/// （StatefulShellRoute 的 IndexedStack 切换不产生 push/pop）。
///
/// `scroll_depth` 依赖各页滚动监听，本轮未接线（留 TODO）。
class PageStayTracker extends NavigatorObserver with WidgetsBindingObserver {
  PageStayTracker({required this.analytics, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// 埋点采集服务（`page_stay` 事件出口）。
  final AnalyticsService analytics;
  final DateTime Function() _now;

  /// 当前路由位置解析（main 在 router 创建后注入，observer 回调内取最新值）。
  String Function()? locationResolver;

  final List<String> _pageStack = <String>[];
  String? _current;
  DateTime? _startedAt;
  bool _paused = false;

  /// 当前停留页（Debug 面板/测试用）。
  String? get currentPageId => _current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final pageId = _resolvePageId();
    _endSegment('navigate');
    _pageStack.add(pageId);
    _startSegment(pageId);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _endSegment('navigate');
    if (_pageStack.isNotEmpty) _pageStack.removeLast();
    _startSegment(_pageStack.isEmpty ? _resolvePageId() : _pageStack.last);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final pageId = _resolvePageId();
    _endSegment('navigate');
    if (_pageStack.isNotEmpty) {
      _pageStack[_pageStack.length - 1] = pageId;
    } else {
      _pageStack.add(pageId);
    }
    _startSegment(pageId);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _endSegment('navigate');
    if (_pageStack.isNotEmpty) _pageStack.removeLast();
    if (_pageStack.isNotEmpty) _startSegment(_pageStack.last);
  }

  /// Tab 切换（HomeShell 底栏点按；同页重按为 no-op）。
  void onTabSwitch(String pageId) {
    if (pageId == _current) return;
    _endSegment('tab_switch');
    if (_pageStack.isNotEmpty) {
      _pageStack[_pageStack.length - 1] = pageId;
    } else {
      _pageStack.add(pageId);
    }
    _startSegment(pageId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 退后台即结算一段（§4.2：暂停计时，end_reason=background）。
        if (!_paused) {
          _endSegment('background');
          _paused = true;
        }
      case AppLifecycleState.resumed:
        // 回前台构成同 session 时新开一段（同页继续计时）。
        if (_paused) {
          _paused = false;
          final current = _current;
          if (current != null) _startSegment(current);
        }
    }
  }

  String _resolvePageId() {
    final resolver = locationResolver;
    if (resolver == null) return 'unknown';
    return pageIdForLocation(resolver());
  }

  void _startSegment(String pageId) {
    _current = pageId;
    _startedAt = _now();
  }

  void _endSegment(String endReason) {
    final pageId = _current;
    final startedAt = _startedAt;
    _startedAt = null;
    if (pageId == null || startedAt == null) return;
    final stayMs = _now().difference(startedAt).inMilliseconds;
    analytics.track(
      'page_stay',
      properties: <String, Object?>{
        'page_id': pageId,
        'stay_ms': stayMs < 0 ? 0 : stayMs,
        'end_reason': endReason,
      },
    );
  }
}
