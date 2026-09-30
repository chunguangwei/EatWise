import 'package:eatwise/features/fasting/domain/fasting_types.dart';

/// 断食周期结果本地（CycleResult 枚举名）↔ 服务端 result 串映射（/sync
/// fastingRecord 通道纯函数；on_track 进行中不产生本地关闭行，不在映射内）。

/// 本地 CycleResult 枚举名 → 服务端 result（/sync 上行口径）。未知枚举名按
/// qualified 兜底。
String serverResultNameOf(String localResultName, {required bool qualified}) {
  if (localResultName == CycleResult.brokenEarly.name) return 'broken';
  if (localResultName == CycleResult.completedEarlyPass.name) {
    return 'ended_early';
  }
  if (localResultName == CycleResult.makeup.name) return 'makeup';
  if (localResultName == CycleResult.completedOnTime.name ||
      localResultName == CycleResult.completedExtended.name) {
    return 'completed';
  }
  return qualified ? 'completed' : 'broken';
}

/// 服务端 result → 本地 CycleResult 枚举名（/sync 下行口径）。
///
/// 2026-09-30：makeup 不再塌缩为 [CycleResult.completedOnTime]，
/// 保留独立身份（补签只计达标、不计断食时长）。
String localResultNameOf(String serverResult, {required int extendedMinutes}) {
  switch (serverResult) {
    case 'broken':
      return CycleResult.brokenEarly.name;
    case 'ended_early':
      return CycleResult.completedEarlyPass.name;
    case 'makeup':
      return CycleResult.makeup.name;
    case 'completed':
      return extendedMinutes > 0
          ? CycleResult.completedExtended.name
          : CycleResult.completedOnTime.name;
    default: // 未知终态：按到点完成展示（达标口径保守兜底）
      return CycleResult.completedOnTime.name;
  }
}

/// 该本地终态是否代表「用户真实断食过」（补签不是）。
///
/// 时长类统计（趋势折线/平均时长/最长单次/累计时长）必须按本判定过滤，
/// 达标类统计（三态格/连胜/达标率）不过滤。
bool isRealFastResult(String localResultName) =>
    localResultName != CycleResult.makeup.name;
