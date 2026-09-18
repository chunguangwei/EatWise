import 'dart:io' show SecurityContext;

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/cert_pinning.dart';
import 'package:eatwise/core/network/token_store.dart';

/// 通用请求头（契约 §1.4/§1.7）：
/// - `Accept-Language` 跟随 slang 当前语言（D-15，切换语言后即时生效）；
/// - `X-Timezone` 携带 IANA 名称，服务端换算本地自然日（D-07）。
final class ApiHeadersInterceptor extends Interceptor {
  ApiHeadersInterceptor({required this.localeTag, required this.timezoneName});

  /// 当前语言标签（如 `zh-CN` / `en`）。
  final String Function() localeTag;

  /// 设备时区 IANA 名称（如 `Asia/Shanghai`）。
  final String Function() timezoneName;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Accept-Language'] = localeTag();
    options.headers['X-Timezone'] = timezoneName();
    handler.next(options);
  }
}

/// 成功信封解包（契约 §1.3）：`{data, meta}` → 响应体直接为 `data`，
/// `meta.serverTime`/`requestId` 挂到 `response.extra` 供时钟校准与排查。
final class EnvelopeInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final body = response.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) {
      final meta = body['meta'];
      if (meta is Map<String, dynamic>) {
        response.extra['serverTime'] = meta['serverTime'];
        response.extra['requestId'] = meta['requestId'];
      }
      response.data = body['data'];
    }
    handler.next(response);
  }
}

/// 错误映射（拦截链最后一环）：DioException → [ApiException] 领域异常，
/// 错误信封三段式解包见 [apiExceptionFromDio]。
final class ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiExceptionFromDio(err),
      ),
    );
  }
}

/// dio 实例工厂：装配请求头 → 认证（401 refresh 重放）→ 信封解包 → 错误映射。
///
/// [localeTag]/[timezoneName] 由集成方注入（slang 当前语言 / tz.local）；
/// [onSessionCleared] 在 refresh 失败清会话后回调（跳登录）。
/// [pinnedSecurityContext] 非空时对主 Dio 与 refresh 裸 Dio 启用自签名
/// 证书锁定（仅生产 https://wcg.polin.tech，见 cert_pinning.dart）。
Dio createApiDio({
  ApiConfig? config,
  TokenStore? tokenStore,
  String Function()? localeTag,
  String Function()? timezoneName,
  void Function()? onSessionCleared,
  SecurityContext? pinnedSecurityContext,
}) {
  final resolvedConfig = config ?? ApiConfig();
  final dio = Dio(
    BaseOptions(
      baseUrl: resolvedConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  );
  if (pinnedSecurityContext != null) {
    applyCertPinning(dio, pinnedSecurityContext);
  }
  dio.interceptors.add(
    ApiHeadersInterceptor(
      localeTag: localeTag ?? () => 'zh-CN',
      timezoneName: timezoneName ?? () => 'Asia/Shanghai',
    ),
  );
  if (tokenStore != null) {
    // 裸 Dio 仅用于 /auth/refresh（共享 BaseOptions，无拦截器防循环）。
    final refreshDio = Dio(dio.options);
    if (pinnedSecurityContext != null) {
      applyCertPinning(refreshDio, pinnedSecurityContext);
    }
    final authInterceptor = AuthInterceptor(
      tokenStore: tokenStore,
      refreshDio: refreshDio,
      onSessionCleared: onSessionCleared,
    );
    authInterceptor.dio = dio;
    dio.interceptors.add(authInterceptor);
  }
  dio.interceptors
    ..add(EnvelopeInterceptor())
    ..add(ErrorMappingInterceptor());
  return dio;
}

/// UTC ISO8601 毫秒时间戳（契约 §1.4：全部 UTC 存储与传输）。
String toUtcIso8601(DateTime dateTime) => dateTime.toUtc().toIso8601String();
