import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';

/// 饮水记录上行同步（轻量两态 pending/synced，无冲突场景〔假设〕）。
///
/// 复用 /sync/push ops 协议（entity=waterLog，≤[kSyncPushBatchSize]/批）：
/// - 普通 pending 行 → create op（幂等键 = 行 clientRequestId，重试复用）；
/// - tombstone 行（已上行后的 D-11 撤销）→ delete op（serverId +
///   payload.clientRequestId 兜底定位，〔假设〕服务端软删）。
///
/// 结果处理：create applied → 回填 serverId 转 synced；delete applied 或
/// NOT_FOUND → 本地物理清除；网络/5xx/429/401 → 保持 pending 下轮重试。
final class RemoteWaterLogSync {
  RemoteWaterLogSync({required this.dio});

  /// 已装配 dio。
  final Dio dio;

  bool _online = true;

  /// 最近一次请求结果推断的在线状态（与 RemoteRecordSync 同口径）。
  bool get isOnline => _online;

  /// 上行该用户全部 pending 饮水记录（含 tombstone）。
  Future<void> pushPending(AppDatabase db, String userId) =>
      withApiSession(dio, () => _pushPending(db, userId), userId: userId);

  Future<void> _pushPending(AppDatabase db, String userId) async {
    final rows = await db.waterLogDao.pendingForUser(userId);
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

  Future<void> _pushChunk(AppDatabase db, List<WaterLog> chunk) async {
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
            await db.waterLogDao.deleteLog(row.localId);
          } else {
            final rawServerId = syncPushServerEntry(result)?['id'];
            if (rawServerId is! String || rawServerId.isEmpty) {
              await _writeError(db, row, kInvalidPushResponse);
              continue;
            }
            await db.waterLogDao.applyServerRow(
              row.localId,
              WaterLogsCompanion(
                serverId: Value(rawServerId),
                syncState: Value(WaterSyncState.synced),
                lastError: const Value(null),
              ),
            );
          }
        } else if (row.deleted && status == 'error' && code == 'NOT_FOUND') {
          await db.waterLogDao.deleteLog(row.localId);
        } else if (!row.deleted &&
            status == 'error' &&
            code == 'VALIDATION_ERROR') {
          await db.waterLogDao.deleteLog(row.localId);
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

  Future<void> _writeError(AppDatabase db, WaterLog row, String code) {
    checkActiveSession();
    return db.waterLogDao.applyServerRow(
      row.localId,
      WaterLogsCompanion(
        syncState: Value(WaterSyncState.pending),
        lastError: Value(code),
      ),
    );
  }

  /// WaterLog → sync/push op（两态：仅 create/delete，无 update）。
  Map<String, dynamic> _opFor(WaterLog row) {
    if (row.deleted) {
      return <String, dynamic>{
        'clientRequestId': row.clientRequestId,
        'entity': 'waterLog',
        'op': 'delete',
        if (row.serverId != null) 'serverId': row.serverId,
        'payload': <String, dynamic>{'clientRequestId': row.clientRequestId},
      };
    }
    return <String, dynamic>{
      'clientRequestId': row.clientRequestId,
      'entity': 'waterLog',
      'op': 'create',
      'payload': <String, dynamic>{
        'amountMl': row.amountMl,
        'loggedAt': row.datetimeUtc,
        'localDate': row.localDate,
      },
    };
  }
}
