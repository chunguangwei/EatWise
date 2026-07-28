import 'dart:convert';

import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// streak 本地状态存储（离线推演快照 + 断签弹窗频控）。
abstract interface class StreakLocalStore {
  /// 读取本地推演引擎快照；无（或损坏）返回 null。
  StreakEngine? loadEngine();

  /// 覆盖写引擎快照。
  void saveEngine(StreakEngine engine);

  /// 已自动弹出过的断签日（频控：每个断签日只自动弹 1 次，§4.1）。
  Set<String> loadShownBreakPopups();

  /// 记录某断签日已自动弹出。
  void markBreakPopupShown(String missedDate);

  /// F2 上行幂等键（按归属日稳定，重试复用，§2.2）。
  String? loadReportRequestId(String attributionDate);

  /// 记录 F2 上行幂等键。
  void saveReportRequestId(String attributionDate, String clientRequestId);
}

/// SharedPreferences 实现（MVP 单用户本地键值；写 fire-and-forget）。
final class SharedPreferencesStreakLocalStore implements StreakLocalStore {
  SharedPreferencesStreakLocalStore(this._prefs);

  static const String _keyEngine = 'streak.engine';
  static const String _keyShownPopups = 'streak.shownBreakPopups';
  static const String _keyReportIds = 'streak.reportRequestIds';

  final SharedPreferences _prefs;

  @override
  StreakEngine? loadEngine() {
    final raw = _prefs.getString(_keyEngine);
    if (raw == null) return null;
    try {
      return StreakEngine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null; // 本地数据损坏按初始态处理（服务端 S1 对账恢复）
    }
  }

  @override
  void saveEngine(StreakEngine engine) {
    _prefs.setString(_keyEngine, jsonEncode(engine.toJson()));
  }

  @override
  Set<String> loadShownBreakPopups() {
    return (_prefs.getStringList(_keyShownPopups) ?? const <String>[]).toSet();
  }

  @override
  void markBreakPopupShown(String missedDate) {
    final shown = loadShownBreakPopups()..add(missedDate);
    _prefs.setStringList(_keyShownPopups, shown.toList());
  }

  @override
  String? loadReportRequestId(String attributionDate) {
    final map = _reportIds();
    return map[attributionDate];
  }

  @override
  void saveReportRequestId(String attributionDate, String clientRequestId) {
    final map = _reportIds()..[attributionDate] = clientRequestId;
    _prefs.setString(_keyReportIds, jsonEncode(map));
  }

  Map<String, String> _reportIds() {
    final raw = _prefs.getString(_keyReportIds);
    if (raw == null) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
    } on Object {
      return <String, String>{};
    }
  }
}

/// 内存实现（单元/组件测试用）。
final class InMemoryStreakLocalStore implements StreakLocalStore {
  StreakEngine? _engine;
  final Set<String> _shownPopups = <String>{};
  final Map<String, String> _reportIds = <String, String>{};

  @override
  StreakEngine? loadEngine() => _engine;

  @override
  void saveEngine(StreakEngine engine) => _engine = engine;

  @override
  Set<String> loadShownBreakPopups() => Set.of(_shownPopups);

  @override
  void markBreakPopupShown(String missedDate) => _shownPopups.add(missedDate);

  @override
  String? loadReportRequestId(String attributionDate) =>
      _reportIds[attributionDate];

  @override
  void saveReportRequestId(String attributionDate, String clientRequestId) {
    _reportIds[attributionDate] = clientRequestId;
  }
}
