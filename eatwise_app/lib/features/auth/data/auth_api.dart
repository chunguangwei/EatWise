import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// 登录会话（契约 §5.1：accessToken/refreshToken/expiresIn/user/isNewUser）。
final class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.userId,
    required this.isNewUser,
    this.nickname,
    this.onboardingStatus,
    this.deletionCancelled = false,
  });

  final String accessToken;
  final String refreshToken;

  /// accessToken 有效期（秒）。
  final int expiresIn;
  final String userId;

  /// 无账号则注册（A2）。
  final bool isNewUser;
  final String? nickname;

  /// 服务端引导完成态（none/skipped/completed），与本地引导标志独立。
  final String? onboardingStatus;

  /// 冷静期内登录自动撤销删除申请（合规 §4.3，登录响应携带）。
  final bool deletionCancelled;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return AuthSession(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken']! as String,
      expiresIn: (json['expiresIn']! as num).toInt(),
      isNewUser: json['isNewUser'] == true,
      deletionCancelled: json['deletionCancelled'] == true,
      userId: user is Map<String, dynamic> ? user['id']! as String : '',
      nickname: user is Map<String, dynamic>
          ? user['nickname'] as String?
          : null,
      onboardingStatus: user is Map<String, dynamic>
          ? user['onboardingStatus'] as String?
          : null,
    );
  }
}

/// 发送验证码结果（A1：ttlSec/resendAfterSec）。
final class SmsSendResult {
  const SmsSendResult({required this.ttlSec, required this.resendAfterSec});

  final int ttlSec;

  /// 重发倒计时秒数（默认 60）。
  final int resendAfterSec;
}

/// 认证接口（契约 §3.1：A1 发短信 / A2 手机登录 / A5 刷新 / A6 注销）。
final class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// A1 发送手机验证码（公开接口；本地联调 mock 验证码固定 123456）。
  Future<SmsSendResult> sendSms({
    required String phone,
    String scene = 'login',
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/sms/send',
        data: <String, dynamic>{'phone': phone, 'scene': scene},
        options: Options(extra: const <String, dynamic>{'skipAuth': true}),
      );
      final data = response.data ?? const <String, dynamic>{};
      return SmsSendResult(
        ttlSec: (data['ttlSec'] as num?)?.toInt() ?? 300,
        resendAfterSec: (data['resendAfterSec'] as num?)?.toInt() ?? 60,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// A2 手机号+验证码登录（无账号则注册）。
  Future<AuthSession> loginPhone({
    required String phone,
    required String code,
    String? deviceId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login/phone',
        data: <String, dynamic>{
          'phone': phone,
          'code': code,
          if (deviceId != null)
            'device': <String, dynamic>{'deviceId': deviceId},
        },
        options: Options(extra: const <String, dynamic>{'skipAuth': true}),
      );
      return AuthSession.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// R1 用户名+密码注册（201；失败码 AUTH_USERNAME_TAKEN /
  /// AUTH_PASSWORD_TOO_WEAK，用户名规则 3-20 位字母/数字/下划线）。
  Future<AuthSession> register({
    required String username,
    required String password,
    String? deviceId,
    String? platform,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: <String, dynamic>{
          'username': username,
          'password': password,
          ..._device(deviceId: deviceId, platform: platform),
        },
        options: Options(extra: const <String, dynamic>{'skipAuth': true}),
      );
      return AuthSession.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// R2 用户名+密码登录（200；失败码 AUTH_INVALID_CREDENTIALS）。
  Future<AuthSession> login({
    required String username,
    required String password,
    String? deviceId,
    String? platform,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: <String, dynamic>{
          'username': username,
          'password': password,
          ..._device(deviceId: deviceId, platform: platform),
        },
        options: Options(extra: const <String, dynamic>{'skipAuth': true}),
      );
      return AuthSession.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// R3 修改密码（需 Bearer；成功后服务端吊销全部 refresh token，
  /// 客户端须清本地会话回登录页）。失败码 AUTH_INVALID_CREDENTIALS /
  /// AUTH_PASSWORD_TOO_WEAK。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/password/change',
        data: <String, dynamic>{
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        },
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// 设备字段（契约 DeviceDto：deviceId 必填、platform ∈ ios/android；
  /// deviceId 缺省时整体不下发）。
  Map<String, dynamic> _device({String? deviceId, String? platform}) {
    if (deviceId == null || deviceId.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{
      'device': <String, dynamic>{
        'deviceId': deviceId,
        'platform': platform ?? 'android',
      },
    };
  }

  /// A6 注销当前设备会话（幂等；失败由调用方按「尽力而为」处理）。
  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/logout', data: const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// U1 轻量读取（restore 回填专用）：当前账号引导完成态。
  /// 重装后 Keychain 令牌存活但 SharedPreferences（本地引导标记）被清，
  /// 登录/注册响应不再发生，v1.12.4 的双写没有触发点——须在会话恢复后
  /// 主动拉一次（失败由调用方静默吞掉）。
  Future<String?> fetchOnboardingStatus() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/users/me');
      final user = response.data?['user'];
      return user is Map<String, dynamic>
          ? user['onboardingStatus'] as String?
          : null;
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
