import 'package:dio/dio.dart';
import 'package:eatwise/core/network/token_store.dart';

/// 认证拦截器（契约 §1.2 / 规格 §7.1）：
///
/// - onRequest：注入 `Authorization: Bearer <accessToken>`；
///   `options.extra['skipAuth'] == true` 的请求（登录/发短信/刷新）跳过。
/// - onError：401 且可刷新时，单飞调 `POST /auth/refresh` 换新令牌后
///   **重放原请求一次**（复用同一 clientRequestId，幂等保证重放安全）；
///   refresh 失败 → 清会话并回调 [onSessionCleared]（跳登录）。
final class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.tokenStore,
    required this.refreshDio,
    this.onSessionCleared,
  });

  /// 令牌存储。
  final TokenStore tokenStore;

  /// 独立裸 Dio（无本拦截器，避免 401 循环），仅用于 /auth/refresh。
  final Dio refreshDio;

  /// 主 Dio（重放原请求走完整拦截链：重新注入 token + 信封解包）。
  /// 由工厂在装配完成后注入。
  late final Dio dio;

  /// refresh 失败/无会话时的登出回调（由集成方接到路由门禁）。
  final void Function()? onSessionCleared;

  /// 单飞刷新：并发 401 共享同一次 refresh，避免旧 refreshToken
  /// 重放触发 Reuse Detection 全端登出（契约 §1.2）。
  Future<bool>? _refreshing;

  bool _skipAuth(RequestOptions options) => options.extra['skipAuth'] == true;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_skipAuth(options)) {
      final token = await tokenStore.accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    if (!is401 || _skipAuth(options) || options.extra['retried'] == true) {
      handler.next(err);
      return;
    }
    if (await _refresh()) {
      try {
        final response = await _replay(options);
        handler.resolve(response);
        return;
      } on DioException catch (replayError) {
        handler.next(replayError);
        return;
      }
    }
    handler.next(err);
  }

  /// 刷新令牌；无可刷新会话或刷新失败 → 清会话并通知登出。
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await tokenStore.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      // 从未登录：无会话可清，直接放行 401（由调用方按业务错误处理）。
      return false;
    }
    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: <String, dynamic>{'refreshToken': refreshToken},
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic> &&
          data['accessToken'] is String &&
          data['refreshToken'] is String) {
        await tokenStore.saveTokens(
          accessToken: data['accessToken']! as String,
          refreshToken: data['refreshToken']! as String,
        );
        return true;
      }
    } on DioException {
      // 刷新失败（过期/吊销/重放）→ 走下方清会话。
    }
    await tokenStore.clear();
    onSessionCleared?.call();
    return false;
  }

  /// 重放原请求一次：标记 retried 防循环，token 由 onRequest 重新注入。
  Future<Response<dynamic>> _replay(RequestOptions options) {
    final replayed = RequestOptions(
      method: options.method,
      path: options.path,
      baseUrl: options.baseUrl,
      queryParameters: options.queryParameters,
      data: options.data,
      headers: Map<String, dynamic>.of(options.headers)
        ..remove('Authorization'),
      extra: Map<String, dynamic>.of(options.extra)..['retried'] = true,
      responseType: options.responseType,
      contentType: options.contentType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
    );
    return dio.fetch<dynamic>(replayed);
  }
}
