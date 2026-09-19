import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';

/// 运动记录上行同步（手动记运动/截图导入，2026-09-19 拍板上行；轻量两态
/// pending/synced，无编辑场景——与 RemoteWaterLogSync 同口径）。
///
/// 复用 /sync/push ops 协议（entity=exerciseLog，≤[kSyncPushBatchSize]/批）：
/// - 普通 pending 行 → create op（幂等键 = 行 clientRequestId，重试复用）；
/// - tombstone 行（已上行后的撤销/删除）→ delete op（serverId +
///   payload.clientRequestId 兜底定位，服务端软删）。
///
/// 结果处理：create applied → 回填 serverId 转 synced；delete applied 或
/// NOT_FOUND → 本地物理清除；网络/5xx/429/401 → 保持 pending 下轮重试。
final class RemoteExerciseLogSync {
  RemoteExerciseLogSync({required this.dio});

  /// 已装配 dio。
  final Dio dio;

  bool _online = true;

  /// 最近一次请求结果推断的在线状态（与 RemoteRecordSync 同口径）。
  bool get isOnline => _online;

  /// 上行该用户全部 pending 运动记录（含 tombstone）。
  Future<void> pushPending(AppDatabase db, String userId) async {
    final rows = await db.exerciseLogDao.pendingForUser(userId);
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += kSyncPushBatchSize) {
      final chunk = rows.sublist(
        i,
        i + kSyncPushBatchSize > rows.length
            ? rows.length
            : i + kSyncPushBatchSize,
      );
      await _pushChunk(db, chunk);
    }
  }

  Future<void> _pushChunk(AppDatabase db, List<ExerciseLog> chunk) async {
    late final List<Map<String, dynamic>> results;
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/sync/push',
        data: <String, dynamic>{'ops': chunk.map(_opFor).toList()},
      );
      _online = true;
      results =
          ((response.data?['results'] as List<dynamic>?) ?? const <dynamic>[])
              .cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      final error = toApiException(e);
      if (error is NetworkApiException || error is TimeoutApiException) {
        _online = false;
      }
      // 请求级失败：整批保持 pending，下轮 syncNow 重试（T5 保数据）。
      return;
    }
    final byRequestId = <String, Map<String, dynamic>>{
      for (final r in results) r['clientRequestId']! as String: r,
    };
    for (final row in chunk) {
      final result = byRequestId[row.clientRequestId];
      if (result == null) continue; // 缺结果保持 pending 重试
      final status = result['status'] as String? ?? 'error';
      final code =
          (result['error'] as Map<String, dynamic>?)?['code'] as String? ?? '';
      if (status == 'applied') {
        if (row.deleted) {
          // tombstone 上行成功 → 本地物理清除。
          await db.exerciseLogDao.deleteLog(row.localId);
        } else {
          final serverEntry = result['serverEntry'];
          final serverId = serverEntry is Map<String, dynamic>
              ? serverEntry['id'] as String?
              : null;
          if (serverId != null) {
            await db.exerciseLogDao.markSynced(row.localId, serverId);
          }
        }
      } else if (row.deleted && code == 'NOT_FOUND') {
        // 服务端本无此行（create 未到达）：tombstone 无意义，本地清除。
        await db.exerciseLogDao.deleteLog(row.localId);
      }
      // 其余 error/conflict：保持 pending，下轮重试。
    }
  }

  /// ExerciseLog → sync/push op（两态：仅 create/delete，无 update）。
  Map<String, dynamic> _opFor(ExerciseLog row) {
    if (row.deleted) {
      return <String, dynamic>{
        'clientRequestId': row.clientRequestId,
        'entity': 'exerciseLog',
        'op': 'delete',
        if (row.serverId != null) 'serverId': row.serverId,
        'payload': <String, dynamic>{'clientRequestId': row.clientRequestId},
      };
    }
    return <String, dynamic>{
      'clientRequestId': row.clientRequestId,
      'entity': 'exerciseLog',
      'op': 'create',
      'payload': <String, dynamic>{
        'typeKey': row.typeKey,
        'durationMin': row.durationMin,
        'kcal': row.kcal,
        if (row.steps != null) 'steps': row.steps,
        if (row.source != null) 'source': row.source,
        'loggedAt': row.createdAtUtc,
        'localDate': row.localDate,
      },
    };
  }
}
