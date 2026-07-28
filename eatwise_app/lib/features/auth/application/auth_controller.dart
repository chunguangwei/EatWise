import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 登录态机（restoring → loggedOut / loggedIn）。
enum AuthStatus { restoring, loggedOut, loggedIn }

/// 认证状态（UI 只读；错误码驱动文案分支，message 可直接上屏）。
final class AuthState {
  const AuthState({
    this.status = AuthStatus.restoring,
    this.userId,
    this.isNewUser = false,
    this.sendingCode = false,
    this.loggingIn = false,
    this.errorCode,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? userId;

  /// 本次登录是否新注册（A2 isNewUser）。
  final bool isNewUser;

  /// 「发送验证码」请求在途。
  final bool sendingCode;

  /// 「登录」请求在途。
  final bool loggingIn;

  /// 最近一次失败错误码（如 AUTH_CODE_INVALID / RATE_LIMITED）。
  final String? errorCode;

  /// 服务端本地化文案（可直接上屏）。
  final String? errorMessage;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    bool? isNewUser,
    bool? sendingCode,
    bool? loggingIn,
    String? Function()? errorCode,
    String? Function()? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      isNewUser: isNewUser ?? this.isNewUser,
      sendingCode: sendingCode ?? this.sendingCode,
      loggingIn: loggingIn ?? this.loggingIn,
      errorCode: errorCode != null ? errorCode() : this.errorCode,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

/// 认证控制器（D-13：手机号验证码登录；令牌持久化走 [TokenStore]，
/// 路由门禁翻转走 [AuthGate]）。
final class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required this.api,
    required this.tokenStore,
    required this.gate,
  }) : super(const AuthState());

  /// 认证接口。
  final AuthApi api;

  /// 令牌存储。
  final TokenStore tokenStore;

  /// 路由门禁。
  final AuthGate gate;

  /// 启动时恢复会话：本地有 refreshToken 即视为登录
  /// （accessToken 过期由拦截器 401 refresh 无感续期）。
  Future<void> restore() async {
    final refreshToken = await tokenStore.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      gate.loggedIn = true;
      state = state.copyWith(status: AuthStatus.loggedIn);
    } else {
      state = state.copyWith(status: AuthStatus.loggedOut);
    }
  }

  /// A1 发送验证码；成功返回重发秒数（页面启动倒计时）。
  Future<int> sendCode(String phone) async {
    state = state.copyWith(
      sendingCode: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      final result = await api.sendSms(phone: phone);
      state = state.copyWith(sendingCode: false);
      return result.resendAfterSec;
    } on ApiException catch (e) {
      state = state.copyWith(
        sendingCode: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
  }

  /// A2 手机号+验证码登录；成功持久化令牌并翻转门禁。
  Future<void> login({required String phone, required String code}) async {
    state = state.copyWith(
      loggingIn: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      final session = await api.loginPhone(phone: phone, code: code);
      await tokenStore.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      gate.loggedIn = true;
      state = state.copyWith(
        status: AuthStatus.loggedIn,
        userId: session.userId,
        isNewUser: session.isNewUser,
        loggingIn: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        loggingIn: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
  }

  /// 登出：A6 尽力而为通知服务端，本地清会话并翻转门禁（T15：
  /// 本地未同步数据按 userId 隔离保留，不随登出清除）。
  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // 尽力而为：服务端不可达也允许本地登出。
    }
    await tokenStore.clear();
    gate.loggedIn = false;
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// refresh 失败被拦截器清会话后同步状态（强制回登录页）。
  void onSessionCleared() {
    gate.loggedIn = false;
    state = const AuthState(status: AuthStatus.loggedOut);
  }
}
