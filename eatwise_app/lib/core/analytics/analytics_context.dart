import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';

/// user_id 哈希化匿名 ID（《埋点规范》§1.2/§1.6-4）。
///
/// 〔假设〕规范口径为 `HMAC-SHA256(user_id, salt)` 且 salt 仅数据平台持有；
/// 客户端侧先用内置 pepper 做去标识（明细层不落明文账号），ETL 层可用
/// 平台 salt 重算替换。
String anonymizeUserId(String userId) {
  const pepper = 'eatwise.analytics.client.v1';
  final digest = Hmac(sha256, utf8.encode(pepper)).convert(utf8.encode(userId));
  return 'u_${digest.toString().substring(0, 16)}';
}

/// 记录/帖子 ID 哈希（字典 `record_id_hash` / `post_id_hash`：仅用于事件
/// 配对，不含内容）。
String anonymizedContentId(String rawId) {
  final digest = sha256.convert(utf8.encode(rawId));
  return 'h_${digest.toString().substring(0, 8)}';
}

/// 公共属性注入器（§1.2：由采集层统一注入，业务代码不得手工拼写）。
///
/// platform/os_version 等环境值经构造参数注入（测试可替换）；
/// 未注入时惰性探测 dart:io [Platform]（仅 iOS/Android 为字典枚举值，
/// 其他桌面/测试环境回退 'android' 占位——生产双端不受影响）。
final class AnalyticsContext {
  AnalyticsContext({
    required this.deviceIdentityStore,
    this.userIdResolver,
    String Function()? localeTag,
    String Function()? networkType,
    this.platform,
    this.osVersion,
    String? appVersion,
    String? buildNumber,
    String? sessionId,
  }) : _localeTag = localeTag ?? (() => 'zh-CN'),
       // 〔假设〕网络类型探测（connectivity_plus）留 TODO；缺省 'wifi'。
       _networkType = networkType ?? (() => 'wifi'),
       // 〔假设〕未引入 package_info_plus，缺省跟随 pubspec version。
       _appVersion = appVersion ?? '1.0.0',
       _buildNumber = buildNumber ?? '1',
       sessionId = sessionId ?? newSessionId();

  final DeviceIdentityStore deviceIdentityStore;
  final String? Function()? userIdResolver;
  final String Function() _localeTag;
  final String Function() _networkType;
  final String? platform;
  final String? osVersion;
  final String _appVersion;
  final String _buildNumber;

  /// 会话 ID（`s_yyyymmdd_…`；退后台 >30 秒再回前台轮换，§1.2〔假设〕）。
  String sessionId;

  /// 生成新会话 ID。
  static String newSessionId() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 's_${date}_${_shortUuid()}';
  }

  /// 当前公共属性快照（§1.2 全量；user_id 已 HMAC 匿名化）。
  Map<String, Object?> commonProps({required String clientDate}) {
    final userId = userIdResolver?.call();
    final deviceId = deviceIdentityStore.deviceId();
    return <String, Object?>{
      if (userId != null && userId.isNotEmpty && userId != 'anonymous')
        'user_id': anonymizeUserId(userId)
      else
        'anonymous_id': 'a_${_shortUuid(from: deviceId)}',
      'device_id': deviceId,
      'platform': platform ?? _detectPlatform(),
      'os_version': osVersion ?? _detectOsVersion(),
      'app_version': _appVersion,
      'build_number': _buildNumber,
      'locale': _localeTag(),
      'network': _networkType(),
      'session_id': sessionId,
      'is_first_open_day': deviceIdentityStore.firstOpenDate() == clientDate,
    };
  }

  static String _detectPlatform() {
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } on Object {
      return 'android';
    }
  }

  static String _detectOsVersion() {
    try {
      return Platform.operatingSystemVersion;
    } on Object {
      return 'unknown';
    }
  }

  static String _shortUuid({String? from}) {
    final source =
        from ??
        '${DateTime.now().microsecondsSinceEpoch}${identityHashCode(Object())}';
    return sha256.convert(utf8.encode(source)).toString().substring(0, 8);
  }
}
