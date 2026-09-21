import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;

/// 手动记运动仓库（无 GMS 设备手动兜底；2026-09-19 拍板上行）。
///
/// 两态同步（pending/synced，口径同 WaterLogRepository，无编辑场景）：
/// 入账落本地 pending 队列，由同步引擎（RemoteExerciseLogSync，挂
/// RecordSyncEngine.syncNow 链）批量上行 /sync/push；乐观更新经
/// [watchLogsForDate] / [watchTotalKcalForDate] 流即时可见。
/// 撤销/删除复用 D-11 语义：从未上行 → 物理删除；已上行 → 置 tombstone
/// 待上行 delete op（服务端软删）。
/// 合规边界：仅本仓库落库的用户主动录入/截图确认记录上行；系统健康数据
/// （HealthKit/Health Connect 实时步数）不经本仓库、不出端。
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
    int? steps,
  }) async {
    if (durationMin < 0) {
      throw ArgumentError.value(durationMin, 'durationMin', '时长不能为负');
    }
    if (kcal <= 0) {
      throw ArgumentError.value(kcal, 'kcal', '消耗必须大于 0');
    }
    if (steps != null && steps <= 0) {
      throw ArgumentError.value(steps, 'steps', '步数必须大于 0');
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
        steps: Value(steps),
        localDate: Value(localDateKey(nowUtc)),
        clientRequestId: Value(_uuid()),
        syncState: const Value(ExerciseSyncState.pending),
        createdAtUtc: Value(nowIso),
      ),
    );
    return (await db.exerciseLogDao.getByLocalId(localId))!;
  }

  /// 删除该条（D-11 撤销与弹层删除同一入口；两态口径同
  /// WaterLogRepository.undo）：从未上行 → 物理删除；已上行 → tombstone
  /// （聚合即时排除，待上行 delete op 后物理清除）。返回是否删除成功。
  Future<bool> delete(String localId) async {
    final log = await db.exerciseLogDao.getByLocalId(localId);
    if (log == null || log.deleted) return false;
    if (log.serverId == null && log.syncState == ExerciseSyncState.pending) {
      // 从未上行：直接物理删除，无需 tombstone。
      return await db.exerciseLogDao.deleteLog(localId) > 0;
    }
    await db.exerciseLogDao.markTombstone(localId);
    return true;
  }

  /// 今日全部运动记录（排除 tombstone）——保存前冲突检测用。
  /// 与 [add] 的归属日同口径（同一 `_clock`），保证「查到的冲突」与
  /// 「入账的当天」一致。
  Future<List<ExerciseLog>> todayLogs() {
    return logsForDate(localDateKey(_clock()));
  }

  /// 替换今日记录（华为运动健康等截图是全天汇总，同日重复导入/再录入
  /// 时应更新而非追加，否则当天消耗重复累计）：今日全部非 tombstone 行
  /// 逐条按两态口径删除（见 [delete]），再入账新行。
  ///
  /// 同步语义 = delete ops + create op（服务端协议只有 create/delete
  /// 两态，无 update，见 AGENTS.md），双端口径天然一致。
  /// 返回新行 + 被删旧行快照（D-11 撤销经 [undoReplace] 恢复）。
  Future<ExerciseSaveResult> replaceToday({
    required String typeKey,
    required int durationMin,
    required double kcal,
    String? source,
    int? steps,
  }) async {
    final replaced = await todayLogs();
    final saved = await add(
      typeKey: typeKey,
      durationMin: durationMin,
      kcal: kcal,
      source: source,
      steps: steps,
    );
    for (final log in replaced) {
      await delete(log.localId);
    }
    return ExerciseSaveResult(saved: saved, replaced: replaced);
  }

  /// 撤销一次「替换」：删除新行 + 把快照旧行重新插回（新 localId + 新
  /// clientRequestId，pending 重新上行）。行身份变化可接受——用户可见
  /// 数据恢复即达标；已上行的旧行此前已随替换上行 delete op，恢复即
  /// 服务端新行。
  Future<void> undoReplace({
    required String savedLocalId,
    required List<ExerciseLog> replaced,
  }) async {
    await delete(savedLocalId);
    for (final log in replaced) {
      await db.exerciseLogDao.insertLog(
        ExerciseLogsCompanion(
          localId: Value(_uuid()),
          userId: Value(userId),
          typeKey: Value(log.typeKey),
          durationMin: Value(log.durationMin),
          kcal: Value(log.kcal),
          source: Value(log.source),
          steps: Value(log.steps),
          localDate: Value(log.localDate),
          clientRequestId: Value(_uuid()),
          syncState: const Value(ExerciseSyncState.pending),
          createdAtUtc: Value(log.createdAtUtc),
        ),
      );
    }
  }

  /// 某日运动记录流（弹层今日列表）。
  Stream<List<ExerciseLog>> watchLogsForDate(String localDate) {
    return db.exerciseLogDao.watchLogsForDate(userId, localDate);
  }

  /// 某日运动消耗合计流（kcal；首页预算行 / 数据页消耗卡）。
  Stream<double> watchTotalKcalForDate(String localDate) {
    return db.exerciseLogDao.watchTotalKcalForDate(userId, localDate);
  }

  /// 某日步数合计流（数据页「步数」展示合并：系统步数 + 本合计）。
  Stream<int> watchTotalStepsForDate(String localDate) {
    return db.exerciseLogDao.watchTotalStepsForDate(userId, localDate);
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

/// 一次入账结果：新行 + 「替换」模式下的旧行快照（撤销恢复用；add 模式
/// 快照为空）。
final class ExerciseSaveResult {
  const ExerciseSaveResult({required this.saved, this.replaced = const []});

  /// 新入账的行。
  final ExerciseLog saved;

  /// 被替换掉的旧行快照（按创建时间升序）；空 = 本次是纯新增。
  final List<ExerciseLog> replaced;
}
