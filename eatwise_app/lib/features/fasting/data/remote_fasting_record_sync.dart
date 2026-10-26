import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/fasting/domain/fasting_result_mapping.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 断食记录上行同步端 Provider（两态 pending/synced，挂
/// recordSyncEngineProvider 触发链，与运动/饮水同口径；dio 未装配的
/// 测试/演示环境返回 null，调用方按「未装配跳过」处理）。
final Provider<RemoteFastingRecordSync?> fastingRecordSyncProvider =
    Provider<RemoteFastingRecordSync?>((ref) {
      try {
        return RemoteFastingRecordSync(dio: ref.watch(apiDioProvider));
      } on Object {
        return null;
      }
    });

/// 断食记录上行同步（2026-09-29 拍板 fastingRecord 全量进 /sync：换机/重装
/// 全量恢复断食历史，补齐 GET /fasting/records 近 14 天兜底之外的存量）。
/// 轻量两态 pending/synced，与 RemoteExerciseLogSync 同口径。
///
/// 与 F2 POST /fasting/end 的关系：F2 保留（带窗口校验 + streak 结算语义），
/// 本通道是「记录数据通道」——本地关闭周期落 drift pending 后，既走 F2
/// （StreakController._reportAndRefresh）也经本队列上行 /sync；服务端按
/// 归属日天然幂等键去重（F2 已结算的记录 → applied 返回既有视图，不覆盖）。
///
/// 复用 /sync/push ops 协议（entity=fastingRecord，≤[kSyncPushBatchSize]/批）：
/// - 普通 pending 行 → create op（幂等键 = 行 clientRequestId，重试复用）；
/// - tombstone 行（deleted=true，预留——当前无 UI 触发删除）→ delete op
///   （serverId + payload.clientRequestId 兜底定位，服务端软删）。
///
/// 结果处理：create applied → 回填 serverId 转 synced；delete applied 或
/// NOT_FOUND → 本地物理清除；网络/5xx/429/401 → 保持 pending 下轮重试。
/// 永久性业务错误（VALIDATION_ERROR 等）保持 pending 下轮重试——断食历史
/// 是用户可见数据（数据页趋势），不学饮水/运动「本地清除」口径静默删历史；
/// pending 断食行不阻塞任何其他记录上行，滞留代价仅每轮一次重试。
final class RemoteFastingRecordSync {
  RemoteFastingRecordSync({required this.dio});

  /// 已装配 dio。
  final Dio dio;

  bool _online = true;

  /// 最近一次请求结果推断的在线状态（与 RemoteRecordSync 同口径）。
  bool get isOnline => _online;

  /// 上行该用户全部 pending 断食记录（含 tombstone）。
  Future<void> pushPending(AppDatabase db, String userId) =>
      withApiSession(dio, () => _pushPending(db, userId), userId: userId);

  Future<void> _pushPending(AppDatabase db, String userId) async {
    final rows = await db.fastingRecordDao.pendingForUser(userId);
    checkActiveSession();
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += kSyncPushBatchSize) {
      final chunk = rows.sublist(
        i,
        i + kSyncPushBatchSize > rows.length
            ? rows.length
            : i + kSyncPushBatchSize,
      );
      checkActiveSession();
      await _pushChunk(db, chunk);
    }
  }

  Future<void> _pushChunk(AppDatabase db, List<FastingRecord> chunk) async {
    late final Map<String, Map<String, dynamic>> byRequestId;
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/sync/push',
        data: <String, dynamic>{'ops': chunk.map(_opFor).toList()},
      );
      checkActiveSession();
      _online = true;
      final parsed = syncPushResultsByRequestId(response.data);
      if (parsed == null) {
        for (final row in chunk) {
          await _writeError(db, row, kInvalidPushResponse);
        }
        return;
      }
      byRequestId = parsed;
    } on DioException catch (e) {
      checkActiveSession();
      final error = toApiException(e);
      if (error is SessionChangedException) throw error;
      if (error is NetworkApiException || error is TimeoutApiException) {
        _online = false;
      }
      for (final row in chunk) {
        await _writeError(db, row, error.code);
      }
      return;
    }
    await db.transaction(() async {
      checkActiveSession();
      for (final row in chunk) {
        checkActiveSession();
        final result = byRequestId[row.clientRequestId];
        if (result == null) {
          await _writeError(db, row, 'MISSING_RESULT');
          continue;
        }
        final status = result['status'];
        final code = syncPushErrorCode(result);
        if (status == 'applied') {
          if (row.deleted) {
            await db.fastingRecordDao.deleteRecord(row.localId);
          } else {
            final rawServerId = syncPushServerEntry(result)?['id'];
            if (rawServerId is! String || rawServerId.isEmpty) {
              await _writeError(db, row, kInvalidPushResponse);
              continue;
            }
            await db.fastingRecordDao.markSynced(row.localId, rawServerId);
            await _clearError(db, row);
          }
        } else if (row.deleted && status == 'error' && code == 'NOT_FOUND') {
          await db.fastingRecordDao.deleteRecord(row.localId);
        } else {
          await _writeError(
            db,
            row,
            status == 'conflict' && code.isEmpty
                ? 'VERSION_CONFLICT'
                : code.isEmpty
                ? kInvalidPushResponse
                : code,
          );
        }
      }
      checkActiveSession();
    });
  }

  Future<void> _writeError(AppDatabase db, FastingRecord row, String code) {
    checkActiveSession();
    return (db.update(
      db.fastingRecords,
    )..where((r) => r.localId.equals(row.localId))).write(
      FastingRecordsCompanion(
        syncStatus: const Value(SyncStatus.pending),
        lastError: Value(code),
      ),
    );
  }

  Future<void> _clearError(AppDatabase db, FastingRecord row) {
    return (db.update(db.fastingRecords)
          ..where((r) => r.localId.equals(row.localId)))
        .write(const FastingRecordsCompanion(lastError: Value(null)));
  }

  /// FastingRecord → sync/push op（两态：仅 create/delete，无 update——
  /// 关闭周期不可变；锚点本地 epoch 秒 → 服务端 ISO8601）。
  Map<String, dynamic> _opFor(FastingRecord row) {
    if (row.deleted) {
      return <String, dynamic>{
        'clientRequestId': row.clientRequestId,
        'entity': 'fastingRecord',
        'op': 'delete',
        if (row.serverId != null) 'serverId': row.serverId,
        'payload': <String, dynamic>{'clientRequestId': row.clientRequestId},
      };
    }
    String iso(int epochSec) => DateTime.fromMillisecondsSinceEpoch(
      epochSec * 1000,
      isUtc: true,
    ).toIso8601String();
    return <String, dynamic>{
      'clientRequestId': row.clientRequestId,
      'entity': 'fastingRecord',
      'op': 'create',
      'payload': <String, dynamic>{
        'attributionDate': row.attributionDate,
        'plannedStartAt': iso(row.startUtc),
        'plannedEndAt': iso(row.startUtc + row.plannedSec),
        'actualStartAt': iso(row.startUtc),
        'actualEndAt': iso(row.endUtc),
        'extendedMinutes': row.extendedMinutes,
        'fastedMinutes': (row.actualSec / 60).round(),
        'result': serverResultNameOf(row.result, qualified: row.qualified),
        'isQualified': row.qualified,
        // 同日双端分叉 LWW 仲裁依据（服务端比较既有记录 updatedAt）。
        'updatedAtUtc': row.createdAtUtc,
      },
    };
  }
}
