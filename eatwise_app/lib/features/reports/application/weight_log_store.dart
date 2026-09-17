import 'dart:convert';

import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider, newClientRequestId;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条体重日志（yyyy-MM-dd 归属日 → 体重/体脂 + 同步元数据）。
///
/// 同步口径（阶段 C）：本地优先 + 登录态同步，两态（pending/synced，与饮水
/// 轻量同步一致〔假设：体重无编辑冲突场景，同日覆写即最新〕）；
/// `clientRequestId` 为上行幂等键（同日覆写生成新键，重试复用），
/// `updatedAtUtc` 为下行 LWW 仲裁依据。
final class WeightLogEntry {
  const WeightLogEntry({
    required this.kg,
    required this.clientRequestId,
    required this.updatedAtUtc,
    this.bodyFatPct,
    this.synced = false,
  });

  /// 体重（kg，一位小数）。
  final double kg;

  /// 体脂率（%，可空）。
  final double? bodyFatPct;

  /// 上行幂等键（UUIDv4，§2.2）。
  final String clientRequestId;

  /// 本地最后修改时间（UTC ISO8601，下行合并 LWW 依据）。
  final String updatedAtUtc;

  /// 是否已上行确认（false = pending 待推送）。
  final bool synced;

  WeightLogEntry copyWith({bool? synced}) {
    return WeightLogEntry(
      kg: kg,
      bodyFatPct: bodyFatPct,
      clientRequestId: clientRequestId,
      updatedAtUtc: updatedAtUtc,
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kg': kg,
    if (bodyFatPct != null) 'bodyFatPct': bodyFatPct,
    'clientRequestId': clientRequestId,
    'updatedAtUtc': updatedAtUtc,
    'synced': synced,
  };

  /// 容错解析（脏数据/缺字段返回 null，由调用方剔除）。
  static WeightLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kg = raw['kg'];
    final clientRequestId = raw['clientRequestId'];
    final updatedAtUtc = raw['updatedAtUtc'];
    if (kg is! num || clientRequestId is! String || updatedAtUtc is! String) {
      return null;
    }
    final bodyFatPct = raw['bodyFatPct'];
    return WeightLogEntry(
      kg: kg.toDouble(),
      bodyFatPct: bodyFatPct is num ? bodyFatPct.toDouble() : null,
      clientRequestId: clientRequestId,
      updatedAtUtc: updatedAtUtc,
      synced: raw['synced'] as bool? ?? false,
    );
  }
}

/// 体重日志（阶段 C：本地优先 SharedPreferences + 登录态后台推拉）。
///
/// record 模块体重录入入口（M3 功能点 4）写入本存储，M6 趋势与成长轨迹
/// 经 [WeightLogStore.loadRange] 直接消费。同日重复记录取最新（覆写）。
///
/// 存储按用户隔离（key 含 userId，与写入侧 currentUserIdProvider 同口径）；
/// v1 全局键（`reports.weightLogs.v1`）在首次读取时一次性迁移进当前用户
/// 命名空间（迁移产物全部 pending，登录后随同步上行）。
class WeightLogStore {
  WeightLogStore(SharedPreferences prefs, {this.userId = 'anonymous'})
    : readFn = prefs.getString,
      writeFn = prefs.setString,
      deleteFn = prefs.remove;

  WeightLogStore._({
    required this.userId,
    required this.readFn,
    required this.writeFn,
    required this.deleteFn,
  });

  /// 内存兜底：SharedPreferences 未装配（测试/预览）时降级，进程内有效。
  factory WeightLogStore.inMemory({String userId = 'anonymous'}) {
    final box = <String, String>{};
    return WeightLogStore._(
      userId: userId,
      readFn: (String key) => box[key],
      writeFn: (String key, String value) async {
        box[key] = value;
        return true;
      },
      deleteFn: (String key) async {
        box.remove(key);
        return true;
      },
    );
  }

  static const String _legacyKey = 'reports.weightLogs.v1';
  static const String _keyPrefix = 'reports.weightLogs.v2.';

  /// 归属用户（未登录 anonymous，与记录仓储口径一致）。
  final String userId;

  final String? Function(String key) readFn;
  final Future<bool> Function(String key, String value) writeFn;
  final Future<bool> Function(String key) deleteFn;

  String get _key => '$_keyPrefix$userId';

  Map<String, WeightLogEntry> _loadAll() {
    final raw = readFn(_key);
    if (raw == null || raw.isEmpty) return _migrateLegacy();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, WeightLogEntry>{};
      final result = <String, WeightLogEntry>{};
      for (final entry in decoded.entries) {
        final parsed = WeightLogEntry.fromJson(entry.value);
        if (parsed != null) result[entry.key.toString()] = parsed;
      }
      return result;
    } on FormatException {
      return <String, WeightLogEntry>{};
    }
  }

  /// v1 全局键一次性迁移（yyyy-MM-dd → kg 纯值映射升级为带同步元数据的条目，
  /// 迁移后全部 pending 待上行）。迁移完成即删旧键，仅生效一次。
  Map<String, WeightLogEntry> _migrateLegacy() {
    final legacyRaw = readFn(_legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return <String, WeightLogEntry>{};
    }
    final migrated = <String, WeightLogEntry>{};
    try {
      final decoded = jsonDecode(legacyRaw);
      if (decoded is Map) {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        for (final entry in decoded.entries) {
          if (entry.value is num) {
            migrated[entry.key.toString()] = WeightLogEntry(
              kg: (entry.value as num).toDouble(),
              clientRequestId: newClientRequestId(),
              updatedAtUtc: nowIso,
            );
          }
        }
      }
    } on FormatException {
      return <String, WeightLogEntry>{};
    }
    // 同步写穿 SharedPreferences 内存缓存（setString 返回前已生效），
    // 后续读取不再走迁移分支。
    writeFn(_key, jsonEncode(migrated));
    deleteFn(_legacyKey);
    return migrated;
  }

  /// 读取 [fromDate]～[toDate]（yyyy-MM-dd，含端点）的体重记录。
  Map<String, double> loadRange(String fromDate, String toDate) {
    return <String, double>{
      for (final entry in loadEntries(fromDate, toDate).entries)
        entry.key: entry.value.kg,
    };
  }

  /// 读取 [fromDate]～[toDate]（含端点）的完整条目（含体脂/同步元数据）。
  Map<String, WeightLogEntry> loadEntries(String fromDate, String toDate) {
    final all = _loadAll();
    return <String, WeightLogEntry>{
      for (final entry in all.entries)
        if (entry.key.compareTo(fromDate) >= 0 &&
            entry.key.compareTo(toDate) <= 0)
          entry.key: entry.value,
    };
  }

  /// 写入某日体重（同日复写取最新；生成新幂等键并置 pending 待上行）。
  Future<void> save(String localDate, double kg, {double? bodyFatPct}) async {
    final all = _loadAll();
    all[localDate] = WeightLogEntry(
      kg: kg,
      bodyFatPct: bodyFatPct,
      clientRequestId: newClientRequestId(),
      updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
    await writeFn(_key, jsonEncode(all));
  }

  /// 全部待上行条目（pending，按日期升序）。
  List<MapEntry<String, WeightLogEntry>> pendingEntries() {
    final rows =
        _loadAll().entries.where((entry) => !entry.value.synced).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return rows;
  }

  /// 上行成功回填：仅当当前条目仍是该次上行的幂等键（同日已再覆写时不误标）。
  Future<void> markSynced(String localDate, String clientRequestId) async {
    final all = _loadAll();
    final entry = all[localDate];
    if (entry == null || entry.clientRequestId != clientRequestId) return;
    all[localDate] = entry.copyWith(synced: true);
    await writeFn(_key, jsonEncode(all));
  }

  /// 下行合并（LWW）：本地 pending 条目不动（上行后服务端同日覆写收敛）；
  /// 其余按 updatedAt 取新，远端较新则覆盖并置 synced。
  Future<void> mergeRemote(
    Iterable<
      ({String date, double kg, double? bodyFatPct, String updatedAtUtc})
    >
    remote,
  ) async {
    final all = _loadAll();
    var changed = false;
    for (final entry in remote) {
      final local = all[entry.date];
      if (local != null && !local.synced) continue; // 本地待上行优先
      if (local != null &&
          local.updatedAtUtc.compareTo(entry.updatedAtUtc) >= 0) {
        continue; // 本地不旧于远端
      }
      all[entry.date] = WeightLogEntry(
        kg: entry.kg,
        bodyFatPct: entry.bodyFatPct,
        clientRequestId: newClientRequestId(),
        updatedAtUtc: entry.updatedAtUtc,
        synced: true,
      );
      changed = true;
    }
    if (changed) await writeFn(_key, jsonEncode(all));
  }
}

/// 体重日志装配（按当前用户隔离，与写入侧 currentUserIdProvider 同口径）。
///
/// SharedPreferences 未注入（测试/预览）时降级内存实现，与
/// `analytics_providers` 的兜底口径一致；生产由 main() 注入后自然生效。
final Provider<WeightLogStore> weightLogStoreProvider =
    Provider<WeightLogStore>((ref) {
      try {
        return WeightLogStore(
          ref.watch(sharedPreferencesProvider),
          userId: ref.watch(currentUserIdProvider),
        );
      } on Object {
        return WeightLogStore.inMemory();
      }
    });
