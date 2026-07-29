import 'package:flutter/foundation.dart';

/// 首启隐私授权路由门禁（合规 §4.1：未同意主隐私政策 → /legal/consent，
/// 在任何数据上报之前拦截，见 app_router redirect）。
///
/// ChangeNotifier：并入 GoRouter.refreshListenable，同意落盘即触发
/// redirect 重算放行。
final class PrivacyGate extends ChangeNotifier {
  factory PrivacyGate({required bool agreed}) => PrivacyGate._(agreed);

  PrivacyGate._(this._agreed);

  bool _agreed;

  /// 是否已同意当前版本主隐私政策（启动时由授权存储回填）。
  bool get agreed => _agreed;

  /// 同意状态翻转（首启弹窗同意后置 true）。
  set agreed(bool value) {
    if (value == _agreed) return;
    _agreed = value;
    notifyListeners();
  }
}
