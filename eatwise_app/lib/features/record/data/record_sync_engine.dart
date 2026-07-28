import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录同步引擎（规格 §2.1：App 启动 / 前台恢复 / 登录成功触发）。
///
/// 先批量上行本地 pending（T8），再 syncToken 增量下行入库（§2.4）。
/// 远程端为 Fake（测试/演示注入）时仅做上行重试，下行跳过。
final class RecordSyncEngine {
  RecordSyncEngine({required this.repository, required this.prefs});

  /// 记录仓储。
  final RecordRepository repository;

  /// syncToken 持久化。
  final SharedPreferences prefs;

  static const String _tokenKeyPrefix = 'record_sync_token_';

  String get _tokenKey => '$_tokenKeyPrefix${repository.userId}';

  bool _syncing = false;

  /// 触发一轮同步（并发去抖：在途时直接返回）。
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await repository.retryPending();
      final remote = repository.remote;
      if (remote is RemoteRecordSync) {
        final token = await remote.pullDown(
          repository.db,
          repository.userId,
          prefs.getString(_tokenKey),
        );
        if (token != null) {
          await prefs.setString(_tokenKey, token);
        }
      }
    } on ApiException {
      // 网络/服务端失败：保持现状，下次触发重试（§4.2）。
    } finally {
      _syncing = false;
    }
  }
}
