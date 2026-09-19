import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;

/// 手动记运动仓库（无 GMS 设备手动兜底）。
///
/// 设备级口径：纯本地落库、不上行服务端（无 pending/synced，与饮水两态
/// 不同）。删除即物理删除——D-11 撤销与弹层今日列表删除同一语义；
/// 乐观更新经 [watchLogsForDate] / [watchTotalKcalForDate] 流即时可见。
final class ExerciseLogRepository {
  ExerciseLogRepository({
    required this.db,
    this.undoWindow = const Duration(seconds: 10),
    DateTime Function()? clock,
    this.userId = 'anonymous',
  }) : _clock = clock ?? DateTime.now;

  /// 本地数据库。
  final AppDatabase db;

  /// D-11 撤销窗时长（与饮食/饮水记录一致，默认 10 秒）。
  final Duration undoWindow;

  /// 归属用户（未登录 anonymous，与 RecordRepository 口径一致）。
  final String userId;

  final DateTime Function() _clock;
  final Random _random = Random();

  /// 截图识别导入来源标记（[add] 的 source 参数取值）。
  static const String sourceScreenshot = 'screenshot';

  /// 入账：立即落库（UI 经流即时刷新），返回新记录。
  ///
  /// [kcal] 为入账快照：MET 估算值或用户手改覆盖值，由调用方算好传入。
  /// [durationMin] 允许 0（截图活动统计导入无时长口径）；手动录入由
  /// UI 校验 > 0。[source] null = 手动录入，[sourceScreenshot] = 截图导入。
  Future<ExerciseLog> add({
    required String typeKey,
    required int durationMin,
    required double kcal,
    String? source,
  }) async {
    if (durationMin < 0) {
      throw ArgumentError.value(durationMin, 'durationMin', '时长不能为负');
    }
    if (kcal <= 0) {
      throw ArgumentError.value(kcal, 'kcal', '消耗必须大于 0');
    }
    final nowUtc = _clock().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final localId = _uuid();
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion(
        localId: Value(localId),
        userId: Value(userId),
        typeKey: Value(typeKey),
        durationMin: Value(durationMin),
        kcal: Value(kcal),
        source: Value(source),
        localDate: Value(localDateKey(nowUtc)),
        createdAtUtc: Value(nowIso),
      ),
    );
    return (await db.exerciseLogDao.getByLocalId(localId))!;
  }

  /// 删除该条（物理删除；D-11 撤销与弹层删除同一入口）。返回是否删除成功。
  Future<bool> delete(String localId) async {
    final log = await db.exerciseLogDao.getByLocalId(localId);
    if (log == null) return false;
    return await db.exerciseLogDao.deleteLog(localId) > 0;
  }

  /// 某日运动记录流（弹层今日列表）。
  Stream<List<ExerciseLog>> watchLogsForDate(String localDate) {
    return db.exerciseLogDao.watchLogsForDate(userId, localDate);
  }

  /// 某日运动消耗合计流（kcal；首页预算行 / 数据页消耗卡）。
  Stream<double> watchTotalKcalForDate(String localDate) {
    return db.exerciseLogDao.watchTotalKcalForDate(userId, localDate);
  }

  /// 某日运动消耗合计（一次性读取）。
  Future<double> totalKcalForDate(String localDate) {
    return db.exerciseLogDao.totalKcalForDate(userId, localDate);
  }

  /// 某日全部运动记录（按创建时间升序）。
  Future<List<ExerciseLog>> logsForDate(String localDate) {
    return db.exerciseLogDao.logsForDate(userId, localDate);
  }

  /// UUIDv4（本地主键用，与 RecordRepository 同法）。
  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
