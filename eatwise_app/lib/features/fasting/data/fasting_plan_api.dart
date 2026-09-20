import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';

/// 断食方案上行接口（`PUT /fasting-plans/current`，契约不变形）。
///
/// body：`{ planType: '14:10'|'16:8'|'18:6', eatingWindow: { start, end } }`
/// （HH:mm 本地墙钟；X-Timezone 由 apiDioProvider 拦截器统一携带，D-07）。
/// planType 取方案 id 的 `@` 前缀（自定义窗口 id 为 `16:8@09:00` 式，
/// 预置方案 id 即 planType 本身）；窗口时长与 planType 的一致性校验
/// （时长 = 24h − 禁食时长，否则 400）由服务端执行，客户端经
/// [buildWindow] 构造时天然满足。
///
/// 服务端生效语义：首个方案立即生效；已有方案改动次日 0 点本地生效
/// （D-06），生效同步时序由 FastingPlanSync（脏标记 + 重试）承担。
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
}
