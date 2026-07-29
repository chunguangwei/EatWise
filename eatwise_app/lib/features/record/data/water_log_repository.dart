import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';

/// 本地归属日键（yyyy-MM-dd，D-07 口径：按设备时区换算）。
String localDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// M3 饮水轻量记录仓库（PRD M3 功能点 4）。
///
/// 轻量口径：仅本地落 drift（不上行同步〔假设〕），乐观更新经
/// [watchTotalForDate] 流即时可见；撤销复用 D-11 语义（10 秒吐司内
/// 物理删除，无四态流转）。
final class WaterLogRepository {
  WaterLogRepository({
    required this.db,
    this.undoWindow = const Duration(seconds: 10),
    DateTime Function()? clock,
    this.userId = 'anonymous',
  }) : _clock = clock ?? DateTime.now;

  /// 本地数据库。
  final AppDatabase db;

  /// D-11 撤销窗时长（与饮食记录一致，默认 10 秒）。
  final Duration undoWindow;

  /// 归属用户（未登录 anonymous，与 RecordRepository 口径一致）。
  final String userId;

  final DateTime Function() _clock;
  final Random _random = Random();

  /// 每日饮水目标（毫升，〔假设〕2000：PRD 未定量，标注于记录页累计区）。
  static const int dailyGoalMl = 2000;

  /// 快捷水量档位（毫升，〔假设〕200/300/500 常见杯量，一键入账）。
  static const List<int> quickAmountsMl = <int>[200, 300, 500];

  /// 一键入账：立即落库（UI 经累计流即时刷新），返回新记录。
  Future<WaterLog> add(int amountMl) async {
    if (amountMl <= 0) {
      throw ArgumentError.value(amountMl, 'amountMl', '饮水量必须大于 0');
    }
    final nowUtc = _clock().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final localId = _uuid();
    await db.waterLogDao.insertLog(
      WaterLogsCompanion(
        localId: Value(localId),
        userId: Value(userId),
        amountMl: Value(amountMl),
        datetimeUtc: Value(nowIso),
        localDate: Value(localDateKey(nowUtc)),
        createdAtUtc: Value(nowIso),
      ),
    );
    return (await db.waterLogDao.getByLocalId(localId))!;
  }

  /// D-11 撤销：撤回该条（物理删除），返回是否撤销成功。
  Future<bool> undo(String localId) async {
    return await db.waterLogDao.deleteLog(localId) > 0;
  }

  /// 当日累计饮水量流（毫升）。
  Stream<int> watchTotalForDate(String localDate) {
    return db.waterLogDao.watchTotalForDate(userId, localDate);
  }

  /// 某日累计饮水量（一次性读取）。
  Future<int> totalForDate(String localDate) {
    return db.waterLogDao.totalForDate(userId, localDate);
  }

  /// 某日全部饮水记录（按时间升序）。
  Future<List<WaterLog>> logsForDate(String localDate) {
    return db.waterLogDao.logsForDate(userId, localDate);
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
