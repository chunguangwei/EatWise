import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';

/// 认证拦截器（契约 §1.2 / 规格 §7.1）：
///
/// - onRequest：仅对当前 API 同源请求注入 `Authorization: Bearer <accessToken>`；
///   `options.extra['skipAuth'] == true` 的请求（登录/发短信/刷新/图片）跳过。
/// - onError：仅当前 API 同源请求的 401 可触发单飞 `POST /auth/refresh`，
///   换新令牌后**重放原请求一次**（复用同一 clientRequestId，幂等保证重放安全）；
///   refresh 失败 → 清会话并回调 [onSessionCleared]（跳登录）。
final class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStore,
    required this.refreshDio,
    required String apiBaseUrl,
    this.onSessionCleared,
  }) : _apiBaseUri = Uri.parse(apiBaseUrl);

  /// 令牌存储。
  final TokenStore tokenStore;

  /// 独立裸 Dio（无本拦截器，避免 401 循环），仅用于 /auth/refresh。
  final Dio refreshDio;

  final Uri _apiBaseUri;

  /// 主 Dio（重放原请求走完整拦截链：重新注入 token + 信封解包）。
  /// 由工厂在装配完成后注入。
  late final Dio dio;

  /// refresh 失败/无会话时的登出回调（由集成方接到路由门禁）。
  final void Function()? onSessionCleared;

  /// 单飞刷新：并发 401 共享同一次 refresh，避免旧 refreshToken
  /// 重放触发 Reuse Detection 全端登出（契约 §1.2）。
  Future<bool>? _refreshing;
  int? _refreshingEpoch;

  bool _skipAuth(RequestOptions options) => options.extra['skipAuth'] == true;

  bool _isApiRequest(RequestOptions options) {
    final target = options.uri;
    if (!_isHttp(_apiBaseUri) ||
        !_isHttp(target) ||
        _apiBaseUri.userInfo.isNotEmpty ||
        target.userInfo.isNotEmpty) {
      return false;
    }
    return target.scheme == _apiBaseUri.scheme &&
        target.host == _apiBaseUri.host &&
        _effectivePort(target) == _effectivePort(_apiBaseUri);
  }

  bool _isHttp(Uri uri) =>
      uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https');

  int? _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme) {
      'http' => 80,
      'https' => 443,
      _ => null,
    };
  }

  /// 401 是否为「访问令牌失效」类错误（触发 refresh 重放）。
  ///
  /// 业务 401（如修改密码旧密码错误 AUTH_INVALID_CREDENTIALS）不是
  /// 令牌过期，必须原样上抛、不得触发 refresh/清会话。信封缺失或
  /// 无法解析时保守视为令牌失效（维持既有续期行为）。
  bool _isTokenInvalid(Response<dynamic>? response) {
    final body = response?.data;
    if (body is! Map) return true;
    final error = body['error'];
    if (error is! Map) return true;
    final code = error['code'];
    if (code is! String) return true;
    return code == 'AUTH_TOKEN_INVALID' ||
        code == 'AUTH_TOKEN_EXPIRED' ||
        code == 'AUTH_REFRESH_REUSED';
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_skipAuth(options) && _isApiRequest(options)) {
      final lease =
          options.extra[requestSessionLeaseKey] as SessionLease? ??
          SessionLease.current ??
          SessionLease(tokenStore);
      options.extra[requestSessionLeaseKey] = lease;
      final snapshot = await tokenStore.snapshot();
      if (!lease.isCurrent || snapshot.epoch != lease.epoch) {
        handler.reject(_sessionChanged(options));
        return;
      }
      final token = snapshot.accessToken;
      options.headers.remove('Authorization');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  DioException _sessionChanged(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.cancel,
    error: const SessionChangedException(),
  );

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final lease =
        response.requestOptions.extra[requestSessionLeaseKey] as SessionLease?;
    if (lease != null && !lease.isCurrent) {
      handler.reject(_sessionChanged(response.requestOptions));
      return;
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final lease = options.extra[requestSessionLeaseKey] as SessionLease?;
    if (lease != null && !lease.isCurrent) {
      handler.next(_sessionChanged(options));
      return;
    }
    final is401 = err.response?.statusCode == 401;
    if (!is401 ||
        _skipAuth(options) ||
        !_isApiRequest(options) ||
        options.extra['retried'] == true ||
        !_isTokenInvalid(err.response)) {
      handler.next(err);
      return;
    }
    if (lease == null) {
      handler.next(err);
      return;
    }
    // Another request may already have refreshed this session before this 401
    // arrived. Reuse the new token instead of rotating again.
    final snapshot = await tokenStore.snapshot();
    if (!lease.isCurrent || snapshot.epoch != lease.epoch) {
      handler.next(_sessionChanged(options));
      return;
    }
    final alreadyRotated =
        snapshot.accessToken != null &&
        options.headers['Authorization'] != 'Bearer ${snapshot.accessToken}';
    if (alreadyRotated || await _refresh(lease)) {
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
  Future<bool> _refresh(SessionLease lease) {
    if (_refreshingEpoch == lease.epoch && _refreshing != null) {
      return _refreshing!;
    }
    final future = _doRefresh(lease.epoch);
    _refreshingEpoch = lease.epoch;
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) {
        _refreshing = null;
        _refreshingEpoch = null;
      }
    });
  }

  Future<bool> _doRefresh(int epoch) async {
    final snapshot = await tokenStore.snapshot();
    if (tokenStore.sessionEpoch != epoch || snapshot.epoch != epoch) {
      return false;
    }
    final refreshToken = snapshot.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: <String, dynamic>{'refreshToken': refreshToken},
      );
      // Refresh belongs to the login session, not the initiating task. Once the
      // server rotates credentials, disposing that task must not discard them.
      // Every original/replayed request still checks its own lease separately.
      if (tokenStore.sessionEpoch != epoch) return false;
      final data = response.data?['data'];
      if (data is Map<String, dynamic> &&
          data['accessToken'] is String &&
          data['refreshToken'] is String) {
        return tokenStore.rotateIfCurrent(
          epoch: epoch,
          accessToken: data['accessToken']! as String,
          refreshToken: data['refreshToken']! as String,
        );
      }
      return false;
    } on DioException catch (e) {
      // Only an explicit rejection of this still-current session can log out.
      // Offline/5xx and late responses retain the user's current credentials.
      if (e.response?.statusCode == 401 &&
          tokenStore.sessionEpoch == epoch &&
          await tokenStore.clearIfCurrent(epoch)) {
        onSessionCleared?.call();
      }
      return false;
    }
  }

  /// 重放原请求一次：标记 retried 防循环，token 由 onRequest 重新注入。
  Future<Response<dynamic>> _replay(RequestOptions options) {
    final replayed = RequestOptions(
      method: options.method,
      path: options.path,
      baseUrl: options.baseUrl,
      queryParameters: options.queryParameters,
      data: _replayData(options.data),
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

  /// 重放请求体：FormData finalize 一次后不可重发，multipart 上传
  /// （图片发帖）在 401 refresh 后原样重放会抛 StateError，须克隆重建
  /// （dio FormData.clone 保留 boundary 并深拷贝 files）。
  Object? _replayData(Object? data) => data is FormData ? data.clone() : data;
}
