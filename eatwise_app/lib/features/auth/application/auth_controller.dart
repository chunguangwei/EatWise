import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/data/auth_api.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
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
    this.registering = false,
    this.changingPassword = false,
    this.errorCode,
    this.errorMessage,
    this.deletionCancelled = false,
  });

  final AuthStatus status;
  final String? userId;

  /// 本次登录是否新注册（A2 isNewUser）。
  final bool isNewUser;

  /// 冷静期内登录已自动撤销删除申请（合规 §4.3，登录后提示）。
  final bool deletionCancelled;

  /// 「发送验证码」请求在途。
  final bool sendingCode;

  /// 「登录」请求在途。
  final bool loggingIn;

  /// 「注册」请求在途。
  final bool registering;

  /// 「修改密码」请求在途。
  final bool changingPassword;

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
    bool? registering,
    bool? changingPassword,
    bool? deletionCancelled,
    String? Function()? errorCode,
    String? Function()? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      isNewUser: isNewUser ?? this.isNewUser,
      sendingCode: sendingCode ?? this.sendingCode,
      loggingIn: loggingIn ?? this.loggingIn,
      registering: registering ?? this.registering,
      changingPassword: changingPassword ?? this.changingPassword,
      deletionCancelled: deletionCancelled ?? this.deletionCancelled,
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
    this.onboardingGate,
    this.onboardingStore,
  }) : super(const AuthState());

  /// 认证接口。
  final AuthApi api;

  /// 令牌存储。
  final TokenStore tokenStore;

  /// 路由门禁。
  final AuthGate gate;

  /// 新手引导门禁（可选；登录/注册响应 onboardingStatus 为
  /// completed/skipped 时同步为已完成，防止老用户重装被重导）。
  final OnboardingGate? onboardingGate;

  /// 引导存储（可选；服务端 onboardingStatus 下行时**持久化**完成标记——
  /// 仅写内存门禁会在杀进程重开后丢失，老用户重装被重导（v1.12.4 走查）。
  /// 本地标记从此只是服务端状态的缓存）。
  final OnboardingStore? onboardingStore;

  /// 启动时恢复会话：本地有 refreshToken 即视为登录
  /// （accessToken 过期由拦截器 401 refresh 无感续期）。
  /// userId 随令牌持久化、此处一并恢复——否则重启后
  /// currentUserIdProvider 恒 anonymous，历史数据按真实 userId
  /// 查询落空（假空态，v1.2.1 走查 B1）。
  Future<void> restore() async {
    final refreshToken = await tokenStore.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      gate.loggedIn = true;
      state = state.copyWith(
        status: AuthStatus.loggedIn,
        userId: await tokenStore.userId,
      );
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

  /// A2 手机号+验证码登录（备用方式，UI 已降级）；成功持久化令牌并翻转门禁。
  Future<void> loginWithPhone({
    required String phone,
    required String code,
  }) async {
    state = state.copyWith(
      loggingIn: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      final session = await api.loginPhone(phone: phone, code: code);
      await _applySession(session);
      state = state.copyWith(loggingIn: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        loggingIn: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
  }

  /// R1 用户名+密码注册；成功即自动登录（持久化令牌并翻转门禁）。
  Future<void> register({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(
      registering: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      final session = await api.register(
        username: username,
        password: password,
      );
      await _applySession(session);
      state = state.copyWith(registering: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        registering: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
  }

  /// R2 用户名+密码登录；成功持久化令牌并翻转门禁。
  Future<void> loginWithPassword({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(
      loggingIn: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      final session = await api.login(username: username, password: password);
      await _applySession(session);
      state = state.copyWith(loggingIn: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        loggingIn: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
  }

  /// R3 修改密码（需登录）。成功后服务端已吊销全部 refresh token，
  /// 本地立即清会话并翻转门禁 → 路由强制回 /login（契约 §R3）。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(
      changingPassword: true,
      errorCode: () => null,
      errorMessage: () => null,
    );
    try {
      await api.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        changingPassword: false,
        errorCode: () => e.code,
        errorMessage: () => e.message,
      );
      rethrow;
    }
    await tokenStore.clear();
    gate.loggedIn = false;
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// 会话落库 + 门禁翻转（登录/注册共用；服务端 onboardingStatus
  /// 为 completed/skipped 时恢复本地引导完成态——**内存门禁 + 持久化
  /// 存储双写**：只写内存会在杀进程重开后丢失，老用户重装被重导；
  /// 时序上先于路由状态翻转完成，登录后路由直接进首页不闪引导页）。
  Future<void> _applySession(AuthSession session) async {
    await tokenStore.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      userId: session.userId,
    );
    if (session.onboardingStatus == 'completed' ||
        session.onboardingStatus == 'skipped') {
      onboardingStore?.markOnboardingCompleted();
      final onboardingGate = this.onboardingGate;
      if (onboardingGate != null) {
        onboardingGate.completed = true;
      }
    }
    gate.loggedIn = true;
    state = state.copyWith(
      status: AuthStatus.loggedIn,
      userId: session.userId,
      isNewUser: session.isNewUser,
      deletionCancelled: session.deletionCancelled,
    );
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

  /// 清掉残留错误（登录/注册/改密共享 AuthState，进入页面时调用，
  /// 避免上一页的失败文案残留到下一页）。
  void clearError() {
    if (state.errorCode == null && state.errorMessage == null) return;
    state = state.copyWith(errorCode: () => null, errorMessage: () => null);
  }
}
