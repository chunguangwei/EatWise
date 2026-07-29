import 'dart:async';

import 'package:eatwise/core/widget_bridge/home_widget_gateway.dart';
import 'package:flutter/foundation.dart';

/// 小组件点击深链服务（设计规范 §4.5：点击进首页）。
///
/// Android 侧由 `EatWiseWidgetProvider` 用 home_widget 的
/// `HomeWidgetLaunchIntent` 拉起 MainActivity 并携带
/// `eatwise://widget/home`；iOS 侧 Widget 用 `widgetURL` 携带同一 URI。
/// home_widget 插件把 URI 经 `widgetClicked` 流（热启动）与
/// `initiallyLaunchedFromHomeWidget`（冷启动）送达 Dart。
///
/// 当前小组件唯一点击目标是首页（'/'）；后续新增直达路由（如
/// Android 4×2「记一笔」→ /record）时按 `uri.host/path` 在此分发。
final class WidgetDeepLinkService {
  WidgetDeepLinkService({required this.gateway});

  /// 桥接网关（测试可注入替身）。
  final HomeWidgetGateway gateway;

  /// 小组件深链 URI scheme/host（Android/iOS 两侧保持一致）。
  static const String clickUri = 'eatwise://widget/home';

  StreamSubscription<Uri?>? _sub;

  /// 开始监听：冷启动 URI + 点击流统一回调 [onOpenHome]。
  ///
  /// 平台异常（插件未注册等）吞掉记日志——深链失败不影响小组件数据同步。
  void start({required void Function() onOpenHome}) {
    unawaited(
      Future(() async {
        try {
          final initial = await gateway.initialClickUri();
          if (_isHomeClick(initial)) onOpenHome();
        } on Object catch (e) {
          debugPrint('WidgetDeepLinkService 冷启动深链读取失败（已降级）: $e');
        }
      }),
    );
    _sub ??= gateway.clickStream.listen(
      (uri) {
        if (_isHomeClick(uri)) onOpenHome();
      },
      onError: (Object e) {
        debugPrint('WidgetDeepLinkService 点击流异常（已降级）: $e');
      },
    );
  }

  /// 停止监听。
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  static bool _isHomeClick(Uri? uri) {
    if (uri == null) return false;
    return uri.scheme == 'eatwise' && uri.host == 'widget';
  }
}
