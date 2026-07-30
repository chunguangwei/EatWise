import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// 当前用户视图（U1 GET /users/me 子集：手机号已脱敏，合规 §6）。
final class UserMeView {
  const UserMeView({
    required this.id,
    required this.maskedPhone,
    this.deletionStatus,
    this.scheduledDeletionAt,
  });

  final String id;

  /// 脱敏手机号（服务端掩码返回，如 +8613****8000）。
  final String maskedPhone;

  /// 删除预约状态（pending 为冷静期内）。
  final String? deletionStatus;

  /// 预约删除执行时间（UTC，冷静期截止）。
  final DateTime? scheduledDeletionAt;

  factory UserMeView.fromJson(Map<String, dynamic> json) {
    final scheduled = json['scheduledDeletionAt'] as String?;
    return UserMeView(
      id: json['id'] as String? ?? '',
      maskedPhone: json['phone'] as String? ?? '',
      deletionStatus: json['deletionStatus'] as String?,
      scheduledDeletionAt: scheduled != null
          ? DateTime.tryParse(scheduled)
          : null,
    );
  }
}

/// 删除申请状态视图（U5/U6 响应：deletionStatus/scheduledDeletionAt/coolingOffDays）。
final class AccountDeletionView {
  const AccountDeletionView({
    this.deletionStatus,
    this.scheduledDeletionAt,
    this.coolingOffDays = 7,
  });

  final String? deletionStatus;
  final DateTime? scheduledDeletionAt;

  /// 冷静期天数（服务端口径，合规 §4.3〔假设〕7 天）。
  final int coolingOffDays;

  factory AccountDeletionView.fromJson(Map<String, dynamic> json) {
    final scheduled = json['scheduledDeletionAt'] as String?;
    return AccountDeletionView(
      deletionStatus: json['deletionStatus'] as String?,
      scheduledDeletionAt: scheduled != null
          ? DateTime.tryParse(scheduled)
          : null,
      coolingOffDays: (json['coolingOffDays'] as num?)?.toInt() ?? 7,
    );
  }
}

/// 用户端点（契约 §3：U1 读取 / U3 导出 / U5 删除申请 / U6 撤销删除）。
final class UserApi {
  UserApi(this._dio);

  final Dio _dio;

  /// U1 当前用户（含脱敏手机号与删除预约状态）。
  Future<UserMeView> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/users/me');
      final data = response.data ?? const <String, dynamic>{};
      final user = data['user'];
      return UserMeView.fromJson(
        user is Map<String, dynamic> ? user : const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// U3 数据导出（合规 §4.2）：服务端聚合全量个人数据 JSON 直返。
  Future<Map<String, dynamic>> exportMe() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/users/me/export',
        data: const <String, dynamic>{},
      );
      return response.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// U5 申请删除账号（幂等；进入冷静期并吊销全部会话）。
  Future<AccountDeletionView> requestDeletion() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/users/me/deletion',
        data: const <String, dynamic>{},
      );
      return AccountDeletionView.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// U6 冷静期内撤销删除申请（幂等）。
  Future<AccountDeletionView> cancelDeletion() async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/users/me/deletion',
      );
      return AccountDeletionView.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
