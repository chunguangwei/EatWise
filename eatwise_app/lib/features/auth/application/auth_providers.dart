import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 登录态路由门禁（main() override 为持久实例并接入 GoRouter）。
final Provider<AuthGate> authGateProvider = Provider<AuthGate>((ref) {
  return AuthGate();
});

/// 认证接口。
final Provider<AuthApi> authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiDioProvider));
});

/// 认证控制器（登录/登出/会话恢复）。
final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
      return AuthController(
        api: ref.watch(authApiProvider),
        tokenStore: ref.watch(tokenStoreProvider),
        gate: ref.watch(authGateProvider),
      );
    });
