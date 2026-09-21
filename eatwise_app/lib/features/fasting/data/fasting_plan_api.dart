import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';

/// 断食方案接口（`PUT/GET /fasting-plans/current` + F3 `POST /fasting/extend`，
/// 契约不变形）。
///
/// PUT body：`{ planType: '14:10'|'16:8'|'18:6', eatingWindow: { start, end } }`
/// （HH:mm 本地墙钟；X-Timezone 由 apiDioProvider 拦截器统一携带，D-07）。
/// planType 取方案 id 的 `@` 前缀（自定义窗口 id 为 `16:8@09:00` 式，
/// 预置方案 id 即 planType 本身）；窗口时长与 planType 的一致性校验
/// （时长 = 24h − 禁食时长，否则 400）由服务端执行，客户端经
/// [buildWindow] 构造时天然满足。
///
/// 服务端生效语义：首个方案立即生效；已有方案改动次日 0 点本地生效
/// （D-06），生效同步时序由 FastingPlanSync（脏标记 + 重试）承担。
/// GET 下行回填见 [fetchCurrent]（重装/换机恢复）；[extendFast] 为 F3
/// 延长断食上报（D-10 服务端审计），与 F1/F2 同族端点，recordId 经
/// [fetchActiveRecordId]（`GET /fasting/status` 的 activeRecord.id）解析。
class FastingPlanApi {
  FastingPlanApi(this._dio);

  final Dio _dio;

  /// 上行当前方案（幂等 PUT；成功返回即视为该窗口已同步）。
  Future<void> putCurrent(FastingPlan plan) async {
    try {
      await _dio.put<void>(
        '/fasting-plans/current',
        data: <String, dynamic>{
          'planType': plan.id.split('@').first,
          'eatingWindow': <String, String>{
            'start': formatClock(plan.eatStartMinutes),
            'end': formatClock(plan.eatEndMinutes),
          },
        },
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// 下行当前方案（P3）：重建为本地 [FastingPlan]；响应缺字段、窗口时长
  /// 非 6/8/10 小时（服务端演进值）等无法表达的情况返回 null（不回填）。
  ///
  /// 服务端对「从未选过方案」的用户返回 `id: 'default'` 虚拟兜底
  /// （16:8 12:00–20:00，D-03），与客户端 [FastingPlan.plan16x8] 同窗，
  /// 一并重建（回填语义与 D-03 一致）。
  Future<FastingPlan?> fetchCurrent() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/fasting-plans/current',
      );
      final current = response.data?['current'];
      if (current is! Map) return null;
      final window = current['eatingWindow'];
      if (window is! Map) return null;
      final start = _parseClock(window['start']);
      final end = _parseClock(window['end']);
      if (start == null || end == null) return null;
      // 预置窗口（planType 与墙钟一致）直接用预置 id；其余重建为
      // `planType@HH:mm` 自定义 id（同窗口不同 id 经 sameWindow 判等，无害）。
      for (final preset in const [
        FastingPlan.plan16x8,
        FastingPlan.plan14x10,
      ]) {
        if (preset.id == current['planType'] &&
            preset.eatStartMinutes == start &&
            preset.eatEndMinutes == end) {
          return preset;
        }
      }
      final eatingMinutes = end > start ? end - start : end - start + 24 * 60;
      if (eatingMinutes % 60 != 0) return null;
      try {
        return buildWindow(
          eatingHours: eatingMinutes ~/ 60,
          startMinutes: start,
        ).toFastingPlan();
      } on ArgumentError {
        // 进食时长非 6/8/10（服务端演进值）：本地引擎不识别，不回填。
        return null;
      }
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// 进行中断食的服务端记录 ID（F1 `GET /fasting/status` 的 activeRecord.id；
  /// 与 FastingReportApi.fetchActiveFast 同端点，此处只取 F3 所需的 id）。
  /// 无进行中记录返回 null。
  Future<String?> fetchActiveRecordId() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/fasting/status');
      final active = response.data?['activeRecord'];
      if (active is! Map) return null;
      return active['id'] as String?;
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  /// F3 延长断食上报（D-10）。[extendMinutes] 为**本次增量**（步进 30；
  /// 服务端累计 ≤240 自行判定，超限抛 `FASTING_EXTEND_LIMIT`）。
  /// 幂等：同一 [clientRequestId] 重放返回首次结果；payload 变化抛
  /// `IDEMPOTENCY_PAYLOAD_MISMATCH`（队列重试必须复用原键 + 原 payload）。
  Future<void> extendFast({
    required String clientRequestId,
    required String recordId,
    required int extendMinutes,
  }) async {
    try {
      await _dio.post<void>(
        '/fasting/extend',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'recordId': recordId,
          'extendMinutes': extendMinutes,
        },
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// `HH:mm` 墙钟 → 当日分钟数；非法格式返回 null。
int? _parseClock(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}
