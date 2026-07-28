/// 新手引导门禁：路由 redirect 依据（首次进入 → /onboarding）。
///
/// 简单可变标志位（任务约定「用简单标志位判断」）；启动时从引导存储的
/// 完成标志读入，一键启动后置为 true。
library;

final class OnboardingGate {
  OnboardingGate({required this.completed});

  /// 新手引导是否已完成（完成/一键启动后 → true，不再进入 /onboarding）。
  bool completed;
}
