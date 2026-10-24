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
/// 实现基于 shared_preferences（用户态键按 uid 命名空间隔离）；读取为同步
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

  /// 同一周期跨 tick/冷启动保持稳定，用于关闭去重。
  String get stableId => '$startUtc:$plannedEndUtc';

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

  /// 最近关闭周期的稳定标识；没有关闭过返回 null。
  String? loadLastClosedCycleId();

  /// 在清除活动周期前记录关闭标识，防止恢复时重复结算。
  void saveLastClosedCycleId(String id);

  /// 提前破窗后的当日进食窗口结束锚点（T3/T4/T9：以实际破窗时刻为进食
  /// 起点、进食结束锚点不后移〔假设〕）；无提前破窗覆盖时返回 null。
  int? loadEarlyEatEndUtc();

  /// 写入提前破窗覆盖（手动「结束断食」成功时）。
  void saveEarlyEatEndUtc(int utc);

  /// 清除提前破窗覆盖（回到计划窗口轨道后）。
  void clearEarlyEatEndUtc();
}

/// SharedPreferences 实现。所有用户态键按 uid 隔离；旧全局键与匿名键
/// 在首次进入对应命名空间时迁移，已登录侧已有值时不覆盖。
final class SharedPreferencesFastingCycleStore implements FastingCycleStore {
  SharedPreferencesFastingCycleStore(this._prefs, {String Function()? userId})
    : _userId = userId ?? (() => 'anonymous');

  static const String _keyActiveCycle = 'fasting.activeCycle';
  static const String _keyEarlyEatEndUtc = 'fasting.earlyEatEndUtc';
  static const String _keyLastClosedCycle = 'fasting.lastClosedCycle';
  static const List<String> _userKeys = <String>[
    _keyActiveCycle,
    _keyEarlyEatEndUtc,
    _keyLastClosedCycle,
  ];

  final SharedPreferences _prefs;
  final String Function() _userId;
  String? _scopedUserId;

  String _key(String base) {
    _ensureScope();
    return '$base.${_scopedUserId!}';
  }

  void _ensureScope() {
    final uid = _userId();
    if (uid == _scopedUserId) return;
    _scopedUserId = uid;
    for (final base in _userKeys) {
      _move(base, '$base.$uid');
      if (uid != 'anonymous') {
        _move('$base.anonymous', '$base.$uid');
      }
    }
  }

  void _move(String source, String target) {
    if (source == target || !_prefs.containsKey(source)) return;
    if (!_prefs.containsKey(target)) {
      final value = _prefs.get(source);
      if (value is String) {
        _prefs.setString(target, value);
      } else if (value is int) {
        _prefs.setInt(target, value);
      }
    }
    _prefs.remove(source);
  }

  @override
  ActiveCycleSnapshot? loadActiveCycle() {
    final raw = _prefs.getString(_key(_keyActiveCycle));
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
    _prefs.setString(_key(_keyActiveCycle), jsonEncode(snapshot.toJson()));
  }

  @override
  void clearActiveCycle() {
    _prefs.remove(_key(_keyActiveCycle));
  }

  @override
  String? loadLastClosedCycleId() =>
      _prefs.getString(_key(_keyLastClosedCycle));

  @override
  void saveLastClosedCycleId(String id) {
    _prefs.setString(_key(_keyLastClosedCycle), id);
  }

  @override
  int? loadEarlyEatEndUtc() => _prefs.getInt(_key(_keyEarlyEatEndUtc));

  @override
  void saveEarlyEatEndUtc(int utc) {
    _prefs.setInt(_key(_keyEarlyEatEndUtc), utc);
  }

  @override
  void clearEarlyEatEndUtc() {
    _prefs.remove(_key(_keyEarlyEatEndUtc));
  }
}

/// 内存实现（单元/组件测试用）。
final class InMemoryFastingCycleStore implements FastingCycleStore {
  ActiveCycleSnapshot? _cycle;
  String? _lastClosedCycleId;
  int? _earlyEatEndUtc;

  @override
  ActiveCycleSnapshot? loadActiveCycle() => _cycle;

  @override
  void saveActiveCycle(ActiveCycleSnapshot snapshot) => _cycle = snapshot;

  @override
  void clearActiveCycle() => _cycle = null;

  @override
  String? loadLastClosedCycleId() => _lastClosedCycleId;

  @override
  void saveLastClosedCycleId(String id) => _lastClosedCycleId = id;

  @override
  int? loadEarlyEatEndUtc() => _earlyEatEndUtc;

  @override
  void saveEarlyEatEndUtc(int utc) => _earlyEatEndUtc = utc;

  @override
  void clearEarlyEatEndUtc() => _earlyEatEndUtc = null;
}
