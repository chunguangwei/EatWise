import 'dart:convert';

import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量体重日志（SharedPreferences，yyyy-MM-dd → kg）。
///
/// 〔遗留〕record 模块的体重录入入口尚未落地（PRD 记录 Tab 规划含饮水/体重
/// 轻量记录）；录入入口就位后写入本存储即可，M6 趋势与成长轨迹直接生效。
class WeightLogStore {
  WeightLogStore(this._prefs);

  static const String _key = 'reports.weightLogs.v1';

  final SharedPreferences _prefs;

  Map<String, double> _loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, double>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};
      return <String, double>{
        for (final entry in decoded.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } on FormatException {
      return <String, double>{};
    }
  }

  /// 读取 [fromDate]～[toDate]（yyyy-MM-dd，含端点）的体重记录。
  Map<String, double> loadRange(String fromDate, String toDate) {
    final all = _loadAll();
    return <String, double>{
      for (final entry in all.entries)
        if (entry.key.compareTo(fromDate) >= 0 &&
            entry.key.compareTo(toDate) <= 0)
          entry.key: entry.value,
    };
  }

  /// 写入某日体重（同日复写取最新）。
  Future<void> save(String localDate, double kg) async {
    final all = _loadAll();
    all[localDate] = kg;
    await _prefs.setString(_key, jsonEncode(all));
  }
}

/// 体重日志装配。
final Provider<WeightLogStore> weightLogStoreProvider =
    Provider<WeightLogStore>((ref) {
      return WeightLogStore(ref.watch(sharedPreferencesProvider));
    });
