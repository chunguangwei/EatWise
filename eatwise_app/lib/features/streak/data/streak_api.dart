import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// S1 streak 视图（服务端权威，契约 §3.7 / streak.controller `GET /streak`）。
final class ServerStreakView {
  const ServerStreakView({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastQualifiedDate,
    required this.mendCardStock,
    required this.mendCardGrantsThisMonth,
    required this.mendCardExpiresAt,
    required this.mendCardUsableWindowDays,
    required this.mendCardStatus,
  });

  final int currentStreak;
  final int longestStreak;

  /// 最近一个有效达标日（含已补签日，`yyyy-MM-dd`；无则 null）。
  final String? lastQualifiedDate;

  /// 当月补签卡库存（0–2）。
  final int mendCardStock;

  /// 本月发放张数（固定 2，D-12）。
  final int mendCardGrantsThisMonth;

  /// 库存到期日（月末，`yyyy-MM-dd`）。
  final String mendCardExpiresAt;

  /// 可补窗口天数（7，D-12）。
  final int mendCardUsableWindowDays;

  /// 服务端补签卡状态（available / empty / broken）。
  final String mendCardStatus;

  /// 库存所属月份 `yyyy-MM`（由月末到期日推导）。
  String get mendCardMonth => mendCardExpiresAt.substring(0, 7);

  /// 本月已用张数（≈ 发放 − 库存）。
  int get usedThisMonth => (mendCardGrantsThisMonth - mendCardStock).clamp(
    0,
    mendCardGrantsThisMonth,
  );

  factory ServerStreakView.fromJson(Map<String, dynamic> json) {
    final cards = json['makeupCards'] as Map<String, dynamic>? ?? const {};
    return ServerStreakView(
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      lastQualifiedDate: json['lastQualifiedDate'] as String?,
      mendCardStock: (cards['stock'] as num?)?.toInt() ?? 0,
      mendCardGrantsThisMonth: (cards['grantsThisMonth'] as num?)?.toInt() ?? 2,
      mendCardExpiresAt: cards['expiresAt'] as String? ?? '',
      mendCardUsableWindowDays:
          (cards['usableWindowDays'] as num?)?.toInt() ?? 7,
      mendCardStatus: cards['status'] as String? ?? 'empty',
    );
  }
}

/// S3 里程碑条目（`GET /streak/milestones`）。
final class ServerMilestone {
  const ServerMilestone({required this.days, required this.achievedAt});

  final int days;
  final String achievedAt;
}

/// streak 服务端接口（S1 查询 / S2 补签卡 / S3 里程碑；服务端为权威，D-12）。
class StreakApi {
  StreakApi(this._dio);

  final Dio _dio;

  /// S1 当前 streak、历史最长、补签卡状态。
  Future<ServerStreakView> fetchStreak() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/streak');
      return ServerStreakView.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// S2 使用补签卡补签（幂等键 `clientRequestId`，服务端强制窗口/库存规则）。
  Future<ServerStreakView> useMendCard({
    required String clientRequestId,
    required String date,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/streak/makeup',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'date': date,
        },
      );
      return ServerStreakView.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// S3 里程碑达成列表（每档永久解锁一次，§5.1）。
  Future<List<ServerMilestone>> fetchMilestones() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/streak/milestones',
      );
      final items =
          (response.data?['items'] as List<dynamic>? ?? const <dynamic>[]);
      return items
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => ServerMilestone(
              days: (m['days'] as num).toInt(),
              achievedAt: m['achievedAt'] as String? ?? '',
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
