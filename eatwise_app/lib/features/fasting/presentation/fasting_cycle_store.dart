import 'dart:convert';

import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 进行中断食周期的本地持久化（《规格-M2》§3.1：锚点全部 UTC epoch 秒）。
///
/// 延长（D-10）会改写本周期的 `plannedEndUtc` / `eatWindowEndUtc` 锚点，
/// 必须落盘：杀进程/重启后经 `reconcile`（domain）恢复时才能还原
/// 「含延长的周期」，否则延长量丢失。方案本体已由 M1
/// `SharedPreferencesOnboardingStore`（`onboarding.activePlan`）持久化，
/// 本存储只负责「当前周期快照」。
///
/// 实现基于 shared_preferences（MVP 单用户本地键值）；读取为同步
/// （SharedPreferences 内存缓存），写入 fire-and-forget（失败不阻断计时
/// 主流程，重启后最多丢失一次未落盘的延长，按原锚点继续，安全降级）。

/// 进行中断食周期快照（[FastCycle] 的可序列化镜像）。
final class ActiveCycleSnapshot {
  const ActiveCycleSnapshot({
    required this.startUtc,
    required this.plannedEndUtc,
    required this.eatWindowEndUtc,
    required this.extendedMinutes,
  });

  /// 断食开始锚点（UTC epoch 秒）。
  final int startUtc;

  /// 计划进食窗口开始锚点（含延长，UTC epoch 秒）。
  final int plannedEndUtc;

  /// 当日进食窗口结束锚点（随延长同步后移，D-10）。
  final int eatWindowEndUtc;

  /// 本周期累计延长分钟数（步进 30，上限 240，D-10）。
  final int extendedMinutes;

  factory ActiveCycleSnapshot.fromCycle(FastCycle cycle) {
    return ActiveCycleSnapshot(
      startUtc: cycle.startUtc,
      plannedEndUtc: cycle.plannedEndUtc,
      eatWindowEndUtc: cycle.eatWindowEndUtc,
      extendedMinutes: cycle.extendedMinutes,
    );
  }

  static ActiveCycleSnapshot fromJson(Map<String, dynamic> json) {
    return ActiveCycleSnapshot(
      startUtc: json['startUtc']! as int,
      plannedEndUtc: json['plannedEndUtc']! as int,
      eatWindowEndUtc: json['eatWindowEndUtc']! as int,
      extendedMinutes: json['extendedMinutes']! as int,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startUtc': startUtc,
    'plannedEndUtc': plannedEndUtc,
    'eatWindowEndUtc': eatWindowEndUtc,
    'extendedMinutes': extendedMinutes,
  };

  /// 还原为领域实体。
  FastCycle toCycle() {
    return FastCycle(
      startUtc: startUtc,
      plannedEndUtc: plannedEndUtc,
      eatWindowEndUtc: eatWindowEndUtc,
      extendedMinutes: extendedMinutes,
    );
  }
}

/// 周期快照存储抽象（测试可换内存实现）。
abstract interface class FastingCycleStore {
  /// 读取进行中的周期快照；无（或数据损坏）返回 null。
  ActiveCycleSnapshot? loadActiveCycle();

  /// 写入/覆盖当前周期快照（延长后调用）。
  void saveActiveCycle(ActiveCycleSnapshot snapshot);

  /// 周期关闭（完成/破窗）后清除。
  void clearActiveCycle();

  /// 提前破窗后的当日进食窗口结束锚点（T3/T4/T9：以实际破窗时刻为进食
  /// 起点、进食结束锚点不后移〔假设〕）；无提前破窗覆盖时返回 null。
  int? loadEarlyEatEndUtc();

  /// 写入提前破窗覆盖（手动「结束断食」成功时）。
  void saveEarlyEatEndUtc(int utc);

  /// 清除提前破窗覆盖（回到计划窗口轨道后）。
  void clearEarlyEatEndUtc();
}

/// SharedPreferences 实现。
final class SharedPreferencesFastingCycleStore implements FastingCycleStore {
  SharedPreferencesFastingCycleStore(this._prefs);

  static const String _keyActiveCycle = 'fasting.activeCycle';
  static const String _keyEarlyEatEndUtc = 'fasting.earlyEatEndUtc';

  final SharedPreferences _prefs;

  @override
  ActiveCycleSnapshot? loadActiveCycle() {
    final raw = _prefs.getString(_keyActiveCycle);
    if (raw == null) return null;
    try {
      return ActiveCycleSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return null; // 本地数据损坏按无周期处理（防御，锚点可由方案重算）
    }
  }

  @override
  void saveActiveCycle(ActiveCycleSnapshot snapshot) {
    _prefs.setString(_keyActiveCycle, jsonEncode(snapshot.toJson()));
  }

  @override
  void clearActiveCycle() {
    _prefs.remove(_keyActiveCycle);
  }

  @override
  int? loadEarlyEatEndUtc() => _prefs.getInt(_keyEarlyEatEndUtc);

  @override
  void saveEarlyEatEndUtc(int utc) {
    _prefs.setInt(_keyEarlyEatEndUtc, utc);
  }

  @override
  void clearEarlyEatEndUtc() {
    _prefs.remove(_keyEarlyEatEndUtc);
  }
}

/// 内存实现（单元/组件测试用）。
final class InMemoryFastingCycleStore implements FastingCycleStore {
  ActiveCycleSnapshot? _cycle;
  int? _earlyEatEndUtc;

  @override
  ActiveCycleSnapshot? loadActiveCycle() => _cycle;

  @override
  void saveActiveCycle(ActiveCycleSnapshot snapshot) => _cycle = snapshot;

  @override
  void clearActiveCycle() => _cycle = null;

  @override
  int? loadEarlyEatEndUtc() => _earlyEatEndUtc;

  @override
  void saveEarlyEatEndUtc(int utc) => _earlyEatEndUtc = utc;

  @override
  void clearEarlyEatEndUtc() => _earlyEatEndUtc = null;
}
