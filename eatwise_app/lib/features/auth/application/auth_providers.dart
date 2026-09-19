import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 登录态路由门禁（main() override 为持久实例并接入 GoRouter）。
final Provider<AuthGate> authGateProvider = Provider<AuthGate>((ref) {
  return AuthGate();
});

/// 认证接口。
final Provider<AuthApi> authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiDioProvider));
});

/// 认证控制器（登录/注册/改密/登出/会话恢复）。
final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
      return AuthController(
        api: ref.watch(authApiProvider),
        tokenStore: ref.watch(tokenStoreProvider),
        gate: ref.watch(authGateProvider),
        // 引导门禁/存储未装配（如纯认证测试）时降级为不同步。
        onboardingGate: _readOnboardingGate(ref),
        onboardingStore: _readOnboardingStore(ref),
      );
    });

/// 引导门禁读取（未 override 的测试环境会抛 UnimplementedError，降级 null）。
OnboardingGate? _readOnboardingGate(Ref ref) {
  try {
    return ref.read(onboardingGateProvider);
  } on Object {
    return null;
  }
}

/// 引导存储读取（未装配时降级 null：服务端 onboardingStatus 只同步内存门禁）。
OnboardingStore? _readOnboardingStore(Ref ref) {
  try {
    return ref.read(onboardingStoreProvider);
  } on Object {
    return null;
  }
}
