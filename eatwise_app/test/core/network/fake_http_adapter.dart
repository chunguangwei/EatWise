import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 手卷假 HttpClientAdapter（无 mock 框架依赖）：按注册顺序或路径规则
/// 返回预置响应，并记录全部请求供断言。
final class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter({this.fallback});

  /// 路径规则响应（key = 请求 path，如 '/auth/refresh'），按注册顺序消费。
  final Map<String, List<StubResponse>> _byPath =
      <String, List<StubResponse>>{};

  /// 兜底响应（未注册路径走这里）。
  final StubResponse? fallback;

  /// 已收到的请求（断言 header/body/重放用）。
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 已收到的请求体（与 [requests] 同序）。
  final List<Object?> requestBodies = <Object?>[];

  /// 注册某路径的下一次响应。
  void stub(String path, StubResponse response) {
    _byPath.putIfAbsent(path, () => <StubResponse>[]).add(response);
  }

  int requestsTo(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    Object? body = options.data;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      try {
        body = jsonDecode(utf8.decode(bytes));
      } on Object {
        body = utf8.decode(bytes, allowMalformed: true);
      }
    }
    requestBodies.add(body);
    final queue = _byPath[options.path];
    final stub = (queue != null && queue.isNotEmpty)
        ? queue.removeAt(0)
        : fallback;
    if (stub == null) {
      throw StateError('FakeHttpAdapter: 未注册响应 ${options.path}');
    }
    return stub.toResponseBody(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 预置响应（JSON 信封或网络错误）。
final class StubResponse {
  const StubResponse._(this.statusCode, this.body, this.throwError);

  /// JSON 响应（自动包 json content-type）。
  factory StubResponse.json(int statusCode, Object body) =>
      StubResponse._(statusCode, body, null);

  /// 网络错误（无响应，模拟断网）。
  factory StubResponse.networkError(Object error) =>
      StubResponse._(null, null, error);

  /// 原始字节响应（下载场景）：application/octet-stream 且带 content-length，
  /// 供 onReceiveProgress 拿到真实 total。
  factory StubResponse.rawBytes(int statusCode, List<int> bytes) =>
      StubResponse._(statusCode, bytes, null);

  final int? statusCode;
  final Object? body;
  final Object? throwError;

  /// 成功信封（契约 §1.3：{data, meta}）。
  static Map<String, dynamic> envelope(Object data) => <String, dynamic>{
    'data': data,
    'meta': <String, dynamic>{
      'serverTime': '2026-07-27T12:00:00.000Z',
      'requestId': 'req_test',
    },
  };

  /// 错误信封（三段式 code/message/details）。
  static Map<String, dynamic> errorEnvelope(
    String code,
    String message, {
    Map<String, dynamic>? details,
  }) => <String, dynamic>{
    'error': <String, dynamic>{
      'code': code,
      'message': message,
      'details': ?details,
    },
    'meta': <String, dynamic>{
      'serverTime': '2026-07-27T12:00:00.000Z',
      'requestId': 'req_test',
    },
  };

  ResponseBody toResponseBody(RequestOptions options) {
    if (throwError != null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: throwError,
      );
    }
    final b = body;
    if (b is List<int>) {
      return ResponseBody.fromBytes(
        b,
        statusCode!,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/octet-stream'],
          Headers.contentLengthHeader: <String>['${b.length}'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode!,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
