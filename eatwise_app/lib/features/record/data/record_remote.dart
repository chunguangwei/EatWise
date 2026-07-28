import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 记录同步远程端抽象（M7 真实实现走 dio + REST 契约；M3 用 Fake 模拟）。
abstract interface class RecordRemote {
  /// 当前是否在线（离线写入直接落 pending，T2）。
  bool get isOnline;

  /// 上行单条记录（真实实现并入 §2.3 批量 push；幂等键复用 entry.clientRequestId）。
  Future<PushOutcome> push(FoodEntry entry);
}

/// Fake 远程端可注入模式：成功 / 可重试失败 / 离线 / 校验拒绝 / 版本冲突。
enum FakeRemoteMode { success, retryableFailure, offline, reject, conflict }

/// 内存 Fake 远程端（任务约束：不写真实网络）。
///
/// - success：模拟服务端分配 serverId/版本/UTC 时间戳（服务端时钟，§2.4 防腐）；
/// - retryableFailure：模拟 5xx/网络错误（转 pending，T5）；
/// - offline：`isOnline=false` 且 push 返回可重试失败（离线写入，T2）；
/// - reject：模拟 422 校验拒绝（T7 回滚）；
/// - conflict：模拟 409 版本冲突（T6 转 conflicted）。
final class FakeRecordRemote implements RecordRemote {
  FakeRecordRemote({this.mode = FakeRemoteMode.success});

  /// 当前模式（测试中可随时切换，如「先离线在联网」）。
  FakeRemoteMode mode;

  /// 已收到的上行次数（幂等验证用）。
  int pushCount = 0;

  /// 已收到的 clientRequestId 列表（服务端幂等表替身，§2.2）。
  final List<String> receivedRequestIds = <String>[];

  int _serverSeq = 0;

  @override
  bool get isOnline => mode != FakeRemoteMode.offline;

  @override
  Future<PushOutcome> push(FoodEntry entry) async {
    pushCount++;
    switch (mode) {
      case FakeRemoteMode.success:
        // 幂等：同一 clientRequestId 重复上行返回首次结果，不重复分配（§2.2）。
        if (receivedRequestIds.contains(entry.clientRequestId)) {
          return PushAck(
            serverId: entry.serverId ?? 'srv-${entry.clientRequestId}',
            serverVersion: entry.serverVersion ?? entry.localVersion,
            serverUpdatedAtUtc: DateTime.now().toUtc().toIso8601String(),
          );
        }
        receivedRequestIds.add(entry.clientRequestId);
        _serverSeq++;
        return PushAck(
          serverId: 'srv-$_serverSeq',
          serverVersion: entry.localVersion,
          serverUpdatedAtUtc: DateTime.now().toUtc().toIso8601String(),
        );
      case FakeRemoteMode.retryableFailure:
      case FakeRemoteMode.offline:
        return const PushRetryable('NETWORK_ERROR');
      case FakeRemoteMode.reject:
        return const PushReject('VALIDATION_FAILED');
      case FakeRemoteMode.conflict:
        return PushConflict(
          serverVersion: (entry.serverVersion ?? entry.localVersion) + 1,
          serverUpdatedAtUtc: DateTime.now().toUtc().toIso8601String(),
        );
    }
  }
}
