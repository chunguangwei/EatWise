import 'dart:io' show SecurityContext;

import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// API 环境配置（--dart-define=API_BASE_URL / API_ENV 覆盖，契约 §1.1）。
final Provider<ApiConfig> apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig();
});

/// 令牌存储（生产由 main() override 为 [SecureTokenStore]；
/// 测试 override 为 [InMemoryTokenStore]）。
final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>((ref) {
  return InMemoryTokenStore();
});

/// 生产自签名证书锁定上下文（仅 https://wcg.polin.tech 启用）；
/// 资产加载是异步的，由 main() 启动时 await 后 override 注入，缺省 null
/// （http 开发地址/测试）保持系统 CA 默认校验。
final Provider<SecurityContext?> pinnedSecurityContextProvider =
    Provider<SecurityContext?>((ref) => null);

/// 已装配 dio 实例：请求头（Accept-Language 跟随 slang、X-Timezone）→
/// 认证（401 refresh 重放）→ 信封解包 → 错误映射。
///
/// refresh 失败清会话后的登出回调由集成方经
/// [apiSessionClearedHandlerProvider] 注入（接到路由门禁）。
final Provider<Dio> apiDioProvider = Provider<Dio>((ref) {
  return createApiDio(
    config: ref.watch(apiConfigProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    // D-15：slang 当前语言；设置内切换后下次请求即生效。
    localeTag: () => LocaleSettings.currentLocale.languageTag,
    // D-07：IANA 时区名，服务端换算本地自然日。
    timezoneName: () => tz.local.name,
    onSessionCleared: () => ref.read(apiSessionClearedHandlerProvider)?.call(),
    pinnedSecurityContext: ref.watch(pinnedSecurityContextProvider),
  );
});

/// refresh 失败 → 清会话后的登出处理（main() 接 AuthGate 强制回登录页）。
final Provider<void Function()?> apiSessionClearedHandlerProvider =
    Provider<void Function()?>((ref) => null);
