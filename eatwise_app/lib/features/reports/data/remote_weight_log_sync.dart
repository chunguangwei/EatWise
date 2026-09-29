import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';

/// 体重记录远端同步（阶段 C：本地优先 + 登录态后台推拉，两态 pending/synced，
/// 与 RemoteWaterLogSync 同口径〔假设：体重无编辑冲突场景，同日覆写即最新〕）。
///
/// 上行：逐条 POST /v1/weight-logs（服务端幂等 upsert：同 userId+date 覆写，
/// clientRequestId 重放返回首次结果），成功 → [WeightLogStore.markSynced]
/// （回填 serverId 供删除定位）；删除（2026-09-29 拍板）：tombstone 逐条
/// DELETE /v1/weight-logs/:id，ack/404 → 本地物理清除。
/// 下行：GET /v1/weight-logs?from&to 全量区间（logs + tombstones）→
/// [WeightLogStore.mergeRemote] LWW 合并 + tombstone 删除传播。
/// 失败保持 pending 下轮重试（T5 保数据），401/匿名由调用方守门。
final class RemoteWeightLogSync {
  RemoteWeightLogSync({required this.dio});

  /// 已装配 dio（鉴权拦截器随登录态附加 token）。
  final Dio dio;

  bool _online = true;

  /// 最近一次请求结果推断的在线状态（与 RemoteRecordSync 同口径）。
  bool get isOnline => _online;

  /// 一轮完整同步：先上行删除（tombstone），再上行 pending，最后下行合并。
  Future<void> sync(WeightLogStore store) async {
    await pushDeletions(store);
    if (!_online) return; // 上行已判离线：后续跳过，下轮重试
    await pushPending(store);
    if (!_online) return; // 上行已判离线：下行跳过，下轮重试
    await pullDown(store);
  }

  /// 上行该用户全部待删除体重记录（tombstone，按日期升序）：
  /// DELETE /v1/weight-logs/:id（幂等，重复删除 200；他人/缺行 404）。
  /// ack 或 404（服务端本无此行/已被删）→ 本地物理清除。
  Future<void> pushDeletions(WeightLogStore store) async {
    for (final entry in store.pendingDeletions()) {
      final date = entry.key;
      final serverId = entry.value.serverId;
      if (serverId == null) {
        // 防御：tombstone 必带 serverId（remove 只给已上行条目置 tombstone）。
        await store.purgeDeleted(date);
        continue;
      }
      try {
        await dio.delete<Map<String, dynamic>>('/weight-logs/$serverId');
        _online = true;
        await store.purgeDeleted(date);
      } on DioException catch (e) {
        final error = toApiException(e);
        if (error is NetworkApiException || error is TimeoutApiException) {
          _online = false;
          return; // 离线：整批保持 tombstone，下轮 syncNow 重试
        }
        if (error is BusinessApiException && error.httpStatus == 404) {
          // 服务端本无此行（已被删/从未上行成功）：tombstone 无意义，本地清除。
          await store.purgeDeleted(date);
        }
        // 其余 4xx/5xx：本条保持 tombstone 下轮重试，继续后续条目。
      }
    }
  }

  /// 上行该用户全部 pending 体重记录（按日期升序，同日覆写服务端收敛）。
  Future<void> pushPending(WeightLogStore store) async {
    for (final entry in store.pendingEntries()) {
      final date = entry.key;
      final log = entry.value;
      try {
        final response = await dio.post<Map<String, dynamic>>(
          '/weight-logs',
          data: <String, dynamic>{
            'clientRequestId': log.clientRequestId,
            'date': date,
            'weightKg': log.kg,
            'bodyFatPct': log.bodyFatPct,
          },
        );
        _online = true;
        await store.markSynced(
          date,
          log.clientRequestId,
          serverId: response.data?['id'] as String?,
        );
      } on DioException catch (e) {
        final error = toApiException(e);
        if (error is NetworkApiException || error is TimeoutApiException) {
          _online = false;
          return; // 离线：整批保持 pending，下轮 syncNow 重试
        }
        // 4xx/5xx：本条保持 pending 下轮重试，继续后续条目（不阻塞整批）。
      }
    }
  }

  /// 下行区间合并（缺省全量：1970-01-01 ～ 今天）：logs LWW 合并 +
  /// tombstones 删除传播（2026-09-29 拍板：他端删除不再被拉回）。
  Future<void> pullDown(
    WeightLogStore store, {
    String from = '1970-01-01',
    String? to,
  }) async {
    final effectiveTo =
        to ?? DateTime.now().toUtc().toIso8601String().substring(0, 10);
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/weight-logs',
        queryParameters: <String, dynamic>{'from': from, 'to': effectiveTo},
      );
      _online = true;
      final data = response.data ?? const <String, dynamic>{};
      final logs = (data['logs'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map((raw) {
            return (
              date: raw['date'] as String? ?? '',
              kg: (raw['weightKg'] as num?)?.toDouble() ?? 0,
              bodyFatPct: (raw['bodyFatPct'] as num?)?.toDouble(),
              updatedAtUtc: raw['updatedAt'] as String? ?? '',
              serverId: raw['id'] as String?,
            );
          })
          .where((entry) => entry.date.isNotEmpty && entry.kg > 0);
      final tombstones =
          (data['tombstones'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>()
              .map((raw) {
                return (
                  id: raw['id'] as String? ?? '',
                  date: raw['date'] as String? ?? '',
                );
              })
              .where((entry) => entry.date.isNotEmpty);
      await store.mergeRemote(logs, tombstones: tombstones);
    } on DioException catch (e) {
      final error = toApiException(e);
      if (error is NetworkApiException || error is TimeoutApiException) {
        _online = false;
      }
      // 下行失败：保持现状，下轮 syncNow 重试（§4.2）。
    }
  }
}
