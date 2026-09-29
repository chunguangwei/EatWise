import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// F1 服务端进行中断食记录（`GET /fasting/status` 的 activeRecord 子集）。
final class ServerActiveFast {
  const ServerActiveFast({required this.id, required this.attributionDate});

  /// 服务端记录 ID（F2 结束断食上报的 recordId）。
  final String id;

  /// 服务端归属日（D-07；与客户端归属日不一致时以服务端为准）。
  final String attributionDate;
}

/// F4 服务端断食历史记录（`GET /fasting/records` 元素，展示回填用子集）。
final class ServerFastingRecord {
  const ServerFastingRecord({
    required this.id,
    required this.attributionDate,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.extendedMinutes,
    required this.result,
    required this.isQualified,
    this.actualStartAt,
    this.actualEndAt,
    this.fastedMinutes,
  });

  final String id;

  /// 归属日（yyyy-MM-dd，D-07 冻结）。
  final String attributionDate;

  final DateTime plannedStartAt;
  final DateTime plannedEndAt;

  /// null = 进行中（on_track），回填时跳过。
  final DateTime? actualStartAt;
  final DateTime? actualEndAt;

  final int extendedMinutes;

  /// 服务端终态（completed / ended_early / broken / on_track / makeup）。
  final String result;

  /// D-08 达标判定（streak 唯一口径，服务端权威）。
  final bool isQualified;
  final int? fastedMinutes;
}

/// 断食打卡上报接口（F1/F2，达标事件上行供服务端重算 streak，D-12 口径）。
///
/// 接线策略（尽力而为，不阻断本地计时流）：
/// 断食进行中先经 [fetchActiveFast] 让服务端物化进行中记录（F1
/// find-or-create 语义）；周期关闭后用其 recordId 调 [reportEnd]（F2，
/// 幂等键稳定复用），服务端按 D-08 自行判定达标并重算 streak。
class FastingReportApi {
  FastingReportApi(this._dio);

  final Dio _dio;

  /// F1 当前断食状态 → 进行中记录（无进行中周期返回 null）。
  Future<ServerActiveFast?> fetchActiveFast() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/fasting/status');
      final active = response.data?['activeRecord'];
      if (active is! Map<String, dynamic>) return null;
      final id = active['id'] as String?;
      if (id == null) return null;
      return ServerActiveFast(
        id: id,
        attributionDate: active['attributionDate'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// F2 手动结束断食上报（幂等：同一 clientRequestId 重放返回首次结果）。
  Future<void> reportEnd({
    required String clientRequestId,
    required String recordId,
    required DateTime endedAtUtc,
  }) async {
    try {
      await _dio.post<void>(
        '/fasting/end',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'recordId': recordId,
          'endedAt': endedAtUtc.toIso8601String(),
        },
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// F4 断食历史下行（数据页近 7 日趋势展示兜底；attributionDate 闭区间）。
  Future<List<ServerFastingRecord>> fetchRecentRecords({
    required String from,
    required String to,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/fasting/records',
        queryParameters: <String, dynamic>{'from': from, 'to': to},
      );
      final list = response.data ?? const <dynamic>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(
            (r) => ServerFastingRecord(
              id: r['id'] as String? ?? '',
              attributionDate: r['attributionDate'] as String? ?? '',
              plannedStartAt: DateTime.parse(r['plannedStartAt'] as String),
              plannedEndAt: DateTime.parse(r['plannedEndAt'] as String),
              actualStartAt: r['actualStartAt'] == null
                  ? null
                  : DateTime.parse(r['actualStartAt'] as String),
              actualEndAt: r['actualEndAt'] == null
                  ? null
                  : DateTime.parse(r['actualEndAt'] as String),
              extendedMinutes: (r['extendedMinutes'] as num?)?.toInt() ?? 0,
              result: r['result'] as String? ?? '',
              isQualified: r['isQualified'] as bool? ?? false,
              fastedMinutes: (r['fastedMinutes'] as num?)?.toInt(),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
