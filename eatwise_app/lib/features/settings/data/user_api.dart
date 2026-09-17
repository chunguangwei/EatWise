import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// 服务端营养目标快照（GET/PATCH /users/me 的 nutritionTargets 字段）。
final class NutritionTargetsView {
  const NutritionTargetsView({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fallback,
  });

  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;

  /// 服务端是否走了缺基础信息兜底（规格 §1.6）。
  final bool fallback;

  factory NutritionTargetsView.fromJson(Map<String, dynamic> json) {
    return NutritionTargetsView(
      kcal: (json['kcal'] as num?)?.toInt() ?? 0,
      proteinG: (json['proteinG'] as num?)?.toInt() ?? 0,
      carbsG: (json['carbsG'] as num?)?.toInt() ?? 0,
      fatG: (json['fatG'] as num?)?.toInt() ?? 0,
      fallback: json['fallback'] as bool? ?? true,
    );
  }
}

/// 当前用户视图（U1 GET /users/me 子集：手机号已脱敏，合规 §6）。
final class UserMeView {
  const UserMeView({
    required this.id,
    required this.maskedPhone,
    this.deletionStatus,
    this.scheduledDeletionAt,
    this.gender,
    this.birthYear,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.goal,
    this.targetWeightKg,
    this.targetDate,
    this.onboardingStatus,
    this.nutritionTargets,
  });

  final String id;

  /// 脱敏手机号（服务端掩码返回，如 +8613****8000）。
  final String maskedPhone;

  /// 删除预约状态（pending 为冷静期内）。
  final String? deletionStatus;

  /// 预约删除执行时间（UTC，冷静期截止）。
  final DateTime? scheduledDeletionAt;

  /// 生理性别（male/female；未填为 null）。
  final String? gender;

  /// 出生年。
  final int? birthYear;

  /// 身高（cm）。
  final double? heightCm;

  /// 体重（kg）。
  final double? weightKg;

  /// 活动水平（sedentary/light/moderate/high）。
  final String? activityLevel;

  /// 目标（fat_loss/health_metric/routine/trial）。
  final String? goal;

  /// 阶段 B 减重目标：目标体重（kg；未设置为 null）。
  final double? targetWeightKg;

  /// 阶段 B 减重目标：目标日期（YYYY-MM-DD；未设置为 null）。
  final String? targetDate;

  /// 引导状态（none/completed/skipped）。
  final String? onboardingStatus;

  /// 服务端按档案计算的营养目标快照（缺基础信息时 fallback=true）。
  final NutritionTargetsView? nutritionTargets;

  factory UserMeView.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? nutritionTargets,
  }) {
    final scheduled = json['scheduledDeletionAt'] as String?;
    return UserMeView(
      id: json['id'] as String? ?? '',
      maskedPhone: json['phone'] as String? ?? '',
      deletionStatus: json['deletionStatus'] as String?,
      scheduledDeletionAt: scheduled != null
          ? DateTime.tryParse(scheduled)
          : null,
      gender: json['gender'] as String?,
      birthYear: (json['birthYear'] as num?)?.toInt(),
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      activityLevel: json['activityLevel'] as String?,
      goal: json['goal'] as String?,
      targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
      targetDate: json['targetDate'] as String?,
      onboardingStatus: json['onboardingStatus'] as String?,
      nutritionTargets: nutritionTargets != null
          ? NutritionTargetsView.fromJson(nutritionTargets)
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

  /// U1 当前用户（含脱敏手机号、档案字段、营养目标快照与删除预约状态）。
  Future<UserMeView> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/users/me');
      final data = response.data ?? const <String, dynamic>{};
      final user = data['user'];
      final targets = data['nutritionTargets'];
      return UserMeView.fromJson(
        user is Map<String, dynamic> ? user : const <String, dynamic>{},
        nutritionTargets: targets is Map<String, dynamic> ? targets : null,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// U2 修改资料（字段级 LWW）：仅传需变更字段（如
  /// gender/birthYear/heightCm/weightKg/activityLevel/goal/onboardingStatus），
  /// 响应同 U1（含重算后的营养目标快照）。
  Future<UserMeView> patchMe(Map<String, Object?> patch) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: patch,
      );
      final data = response.data ?? const <String, dynamic>{};
      final user = data['user'];
      final targets = data['nutritionTargets'];
      return UserMeView.fromJson(
        user is Map<String, dynamic> ? user : const <String, dynamic>{},
        nutritionTargets: targets is Map<String, dynamic> ? targets : null,
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
