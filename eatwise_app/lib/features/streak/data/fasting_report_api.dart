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
}
