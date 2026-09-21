import 'package:dio/dio.dart';

/// 领域异常（契约 §1.3 错误信封 code/message/details → 客户端分支只认 code）。
sealed class ApiException implements Exception {
  const ApiException({required this.message});

  /// 用户可读文案（服务端按 Accept-Language 本地化，可直接上屏）。
  final String message;

  /// 稳定机器可读码（SCREAMING_SNAKE）。
  String get code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// 网络层失败：连接失败/无网/DNS 等（未收到响应）。
final class NetworkApiException extends ApiException {
  const NetworkApiException([String message = '网络连接失败'])
    : super(message: message);

  @override
  String get code => 'NETWORK_ERROR';
}

/// 请求超时。
final class TimeoutApiException extends ApiException {
  const TimeoutApiException([String message = '请求超时'])
    : super(message: message);

  @override
  String get code => 'TIMEOUT';
}

/// 自定义食物已晋升共享库（服务端 promote 后行 isCustom=false，
/// PATCH/DELETE /foods/custom/:id 必 404）。仓储层捕获 NOT_FOUND 自愈
/// （本地写 contributionStatus=approved）后改抛此码；UI 映射到人话
/// 文案引导走「数据有误？」纠错，而非裸「资源不存在」。
final class FoodApprovedSharedApiException extends ApiException {
  const FoodApprovedSharedApiException() : super(message: '食物已审核进入共享库');

  @override
  String get code => 'FOOD_APPROVED_SHARED';
}

/// 服务端业务错误（4xx/5xx，错误信封三段式）。
final class BusinessApiException extends ApiException {
  const BusinessApiException({
    required this.httpStatus,
    required this.code,
    required super.message,
    this.details,
    this.requestId,
  });

  /// HTTP 状态码。
  final int httpStatus;

  @override
  final String code;

  /// 可选结构化补充（字段错误列表、冲突信息、重试秒数等）。
  final Map<String, dynamic>? details;

  /// 链路追踪 ID（客服/日志排查凭据）。
  final String? requestId;

  /// 是否可重试（网络错误语义：5xx / 429）。
  bool get isRetryable => httpStatus >= 500 || httpStatus == 429;

  /// 429 限流建议的重试秒数（details.retryAfterSec）。
  int? get retryAfterSec => (details?['retryAfterSec'] as num?)?.toInt();
}

/// 任意异常 → 领域异常（配合 ErrorMappingInterceptor：映射后的
/// ApiException 挂在 DioException.error 上）。
ApiException toApiException(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final inner = error.error;
    if (inner is ApiException) return inner;
    return apiExceptionFromDio(error);
  }
  return const NetworkApiException();
}

/// DioException → 领域异常：解析错误信封 {error:{code,message,details}, meta}。
ApiException apiExceptionFromDio(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const TimeoutApiException();
    case DioExceptionType.connectionError:
      return const NetworkApiException();
    case DioExceptionType.badResponse:
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      final response = error.response;
      if (response == null) return const NetworkApiException();
      return businessExceptionFromResponse(response);
  }
}

/// 从响应体解析错误信封；体非信封时按状态码兜底。
BusinessApiException businessExceptionFromResponse(Response<dynamic> response) {
  final status = response.statusCode ?? 0;
  final body = response.data;
  String code = switch (status) {
    401 => 'AUTH_TOKEN_INVALID',
    404 => 'NOT_FOUND',
    409 => 'CONFLICT',
    429 => 'RATE_LIMITED',
    >= 500 => 'INTERNAL_ERROR',
    _ => 'HTTP_$status',
  };
  String message = '请求失败（$status）';
  Map<String, dynamic>? details;
  String? requestId;
  if (body is Map<String, dynamic>) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      if (error['code'] is String) code = error['code']! as String;
      if (error['message'] is String) message = error['message']! as String;
      if (error['details'] is Map<String, dynamic>) {
        details = error['details']! as Map<String, dynamic>;
      }
    }
    final meta = body['meta'];
    if (meta is Map<String, dynamic> && meta['requestId'] is String) {
      requestId = meta['requestId']! as String;
    }
  }
  return BusinessApiException(
    httpStatus: status,
    code: code,
    message: message,
    details: details,
    requestId: requestId,
  );
}
