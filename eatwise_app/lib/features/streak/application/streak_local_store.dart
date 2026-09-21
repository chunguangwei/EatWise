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

/// SharedPreferences 实现（键按用户命名空间隔离，与体重存储 WeightLogStore
/// 同法；写 fire-and-forget）。
///
/// 两级一次性迁移（升级/登录无缝）：
/// - 构造期：旧全局键（`streak.*`，v1.13.2 及更早）rename 进当前用户命名
///   空间（目标键已存在时旧全局值退役——新代际已写入更新的状态）；
/// - [migrateAnonymous]：登录换挂（审计#1，登录迁移器调用），anonymous
///   命名空间并入真实 uid 命名空间。
final class SharedPreferencesStreakLocalStore implements StreakLocalStore {
  SharedPreferencesStreakLocalStore(this._prefs, {this.userId = 'anonymous'}) {
    _migrateLegacyGlobalKeys();
  }

  static const String _keyEngine = 'streak.engine';
  static const String _keyShownPopups = 'streak.shownBreakPopups';
  static const String _keyReportIds = 'streak.reportRequestIds';

  /// 旧全局键（v1.13.2 及更早的无前缀形态）。
  static const List<String> _legacyKeys = <String>[
    _keyEngine,
    _keyShownPopups,
    _keyReportIds,
  ];

  /// 归属用户（未登录 anonymous，与记录仓储口径一致）。
  final String userId;

  final SharedPreferences _prefs;

  String get _engineKey => '$_keyEngine.$userId';
  String get _shownPopupsKey => '$_keyShownPopups.$userId';
  String get _reportIdsKey => '$_keyReportIds.$userId';

  /// 旧全局键一次性迁入当前命名空间（仅 rename 语义：目标键缺失才搬，
  /// 旧键无论如何删除）。anonymous 态无需迁移（新键
  /// `streak.engine.anonymous` 与旧键等价独立，搬不搬都是同一份数据，
  /// 保持不搬以免反复抖）。同步写穿内存缓存（set 返回前已生效）。
  void _migrateLegacyGlobalKeys() {
    if (userId == 'anonymous') return;
    for (final legacy in _legacyKeys) {
      final raw = _prefs.get(legacy);
      if (raw == null) continue;
      final namespaced = '$legacy.$userId';
      if (!_prefs.containsKey(namespaced)) {
        if (raw is String) {
          _prefs.setString(namespaced, raw);
        } else if (raw is List<String>) {
          _prefs.setStringList(namespaced, raw);
        }
      }
      _prefs.remove(legacy);
    }
  }

  /// 登录换挂（审计#1 匿名数据迁移）：anonymous 命名空间并入 [userId]
  /// 命名空间后删除匿名键。合并口径：引擎快照以已登录侧为准（uid 侧
  /// 存在即不搬——服务端 S1 对账随后会覆盖权威值）；断签弹窗记录取并集
  /// （防换挂后重复弹窗）；幂等键表同日以已登录侧为准。
  /// 返回是否有匿名键被处理（调用方幂等标记照常落）。
  static bool migrateAnonymous(SharedPreferences prefs, String userId) {
    var touched = false;
    // 引擎快照：uid 侧缺失才整体搬。
    final anonEngine = prefs.getString('$_keyEngine.anonymous');
    if (anonEngine != null) {
      touched = true;
      if (prefs.getString('$_keyEngine.$userId') == null) {
        prefs.setString('$_keyEngine.$userId', anonEngine);
      }
      prefs.remove('$_keyEngine.anonymous');
    }
    // 断签弹窗记录：并集。
    final anonPopups = prefs.getStringList('$_keyShownPopups.anonymous');
    if (anonPopups != null) {
      touched = true;
      final merged = <String>{
        ...?prefs.getStringList('$_keyShownPopups.$userId'),
        ...anonPopups,
      };
      prefs.setStringList('$_keyShownPopups.$userId', merged.toList());
      prefs.remove('$_keyShownPopups.anonymous');
    }
    // F2 幂等键表：同日以已登录侧为准。
    final anonIds = prefs.getString('$_keyReportIds.anonymous');
    if (anonIds != null) {
      touched = true;
      final uidKey = '$_keyReportIds.$userId';
      final merged = <String, String>{};
      for (final raw in <String>[anonIds, prefs.getString(uidKey) ?? '']) {
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final e in decoded.entries) {
              if (e.value is String) {
                merged[e.key.toString()] = e.value as String;
              }
            }
          }
        } on FormatException {
          // 脏键值忽略（uid 侧在循环第二位：同日覆盖匿名侧）。
        }
      }
      prefs.setString(uidKey, jsonEncode(merged));
      prefs.remove('$_keyReportIds.anonymous');
    }
    return touched;
  }

  @override
  StreakEngine? loadEngine() {
    final raw = _prefs.getString(_engineKey);
    if (raw == null) return null;
    try {
      return StreakEngine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null; // 本地数据损坏按初始态处理（服务端 S1 对账恢复）
    }
  }

  @override
  void saveEngine(StreakEngine engine) {
    _prefs.setString(_engineKey, jsonEncode(engine.toJson()));
  }

  @override
  Set<String> loadShownBreakPopups() {
    return (_prefs.getStringList(_shownPopupsKey) ?? const <String>[]).toSet();
  }

  @override
  void markBreakPopupShown(String missedDate) {
    final shown = loadShownBreakPopups()..add(missedDate);
    _prefs.setStringList(_shownPopupsKey, shown.toList());
  }

  @override
  String? loadReportRequestId(String attributionDate) {
    final map = _reportIds();
    return map[attributionDate];
  }

  @override
  void saveReportRequestId(String attributionDate, String clientRequestId) {
    final map = _reportIds()..[attributionDate] = clientRequestId;
    _prefs.setString(_reportIdsKey, jsonEncode(map));
  }

  Map<String, String> _reportIds() {
    final raw = _prefs.getString(_reportIdsKey);
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
