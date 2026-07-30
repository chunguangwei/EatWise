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

  /// A6 注销当前设备会话（幂等；失败由调用方按「尽力而为」处理）。
  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/logout', data: const <String, dynamic>{});
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
