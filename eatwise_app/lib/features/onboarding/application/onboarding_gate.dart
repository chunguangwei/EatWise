// 新手引导门禁：路由 redirect 依据（首次进入 → /onboarding）。
//
// ChangeNotifier：GoRouter.refreshListenable 之一——restore() 回填路径
// （重装后 Keychain 令牌存活但本地引导标记丢失，异步拉服务端
// onboardingStatus 补写）在首帧后才完成，通知触发 redirect 重算把用户
// 送出 /onboarding；同步翻转点（一键启动/登录）行为不变。
library;

import 'package:flutter/foundation.dart';

final class OnboardingGate extends ChangeNotifier {
  // 公开参数名 completed（私有命名形参不可作具名参数），初始化列表赋值。
  // ignore: prefer_initializing_formals
  OnboardingGate({required bool completed}) : _completed = completed;

  bool _completed;

  /// 新手引导是否已完成（完成/一键启动后 → true，不再进入 /onboarding）。
  bool get completed => _completed;

  set completed(bool value) {
    if (value == _completed) return;
    _completed = value;
    notifyListeners();
  }
}
