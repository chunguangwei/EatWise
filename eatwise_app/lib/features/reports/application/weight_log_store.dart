import 'dart:convert';

import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量体重日志（SharedPreferences，yyyy-MM-dd → kg）。
///
/// record 模块体重录入入口（M3 功能点 4）写入本存储，M6 趋势与成长轨迹
/// 经 [WeightLogStore.loadRange] 直接消费。同日重复记录取最新（覆写）。
class WeightLogStore {
  WeightLogStore(SharedPreferences prefs)
    : _read = (() => prefs.getString(_key)),
      _write = ((value) => prefs.setString(_key, value));

  WeightLogStore._({required this._read, required this._write});

  /// 内存兜底：SharedPreferences 未装配（测试/预览）时降级，进程内有效。
  factory WeightLogStore.inMemory() {
    final box = <String, String>{};
    return WeightLogStore._(
      read: () => box[_key],
      write: (value) async {
        box[_key] = value;
        return true;
      },
    );
  }

  static const String _key = 'reports.weightLogs.v1';

  final String? Function() _read;
  final Future<bool> Function(String value) _write;

  Map<String, double> _loadAll() {
    final raw = _read();
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
    await _write(jsonEncode(all));
  }
}

/// 体重日志装配。
///
/// SharedPreferences 未注入（测试/预览）时降级内存实现，与
/// `analytics_providers` 的兜底口径一致；生产由 main() 注入后自然生效。
final Provider<WeightLogStore> weightLogStoreProvider =
    Provider<WeightLogStore>((ref) {
      try {
        return WeightLogStore(ref.watch(sharedPreferencesProvider));
      } on Object {
        return WeightLogStore.inMemory();
      }
    });
