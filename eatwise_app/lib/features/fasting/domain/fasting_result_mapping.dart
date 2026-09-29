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
  if (localResultName == CycleResult.completedOnTime.name ||
      localResultName == CycleResult.completedExtended.name) {
    return 'completed';
  }
  return qualified ? 'completed' : 'broken';
}

/// 服务端 result → 本地 CycleResult 枚举名（/sync 下行口径，与
/// StreakController._serverResultName 同映射：makeup 等达标行按到点完成展示）。
String localResultNameOf(String serverResult, {required int extendedMinutes}) {
  switch (serverResult) {
    case 'broken':
      return CycleResult.brokenEarly.name;
    case 'ended_early':
      return CycleResult.completedEarlyPass.name;
    case 'completed':
      return extendedMinutes > 0
          ? CycleResult.completedExtended.name
          : CycleResult.completedOnTime.name;
    default: // makeup 等：达标行按到点完成展示
      return CycleResult.completedOnTime.name;
  }
}
