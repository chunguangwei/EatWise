import 'package:flutter/foundation.dart';

/// 登录态路由门禁（与 OnboardingGate 协调：登录态与引导完成是
/// 两个独立标志——未登录 → /login；已登录未完成引导 → /onboarding）。
///
/// ChangeNotifier：作为 GoRouter.refreshListenable，登录态变化即触发
/// redirect 重算。
final class AuthGate extends ChangeNotifier {
  bool _loggedIn = false;

  /// 是否已登录（启动时由 AuthController.restore 回填）。
  bool get loggedIn => _loggedIn;

  /// 登录态翻转（登录成功 / 登出 / refresh 失败清会话）。
  set loggedIn(bool value) {
    if (value == _loggedIn) return;
    _loggedIn = value;
    notifyListeners();
  }
}
