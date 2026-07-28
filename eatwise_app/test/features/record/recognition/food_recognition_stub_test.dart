import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/features/record/recognition/data/food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 远端识别 stub 测试：服务端识别端点未落地前，任何响应/异常
/// 都必须映射为 RecognitionUnavailable（D-16 手动搜索兜底），
/// 绝不产出伪识别结果（诚实性要求）。
void main() {
  Dio dioWith(Future<ResponseBody> Function(RequestOptions options) handler) {
    return Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _FakeAdapter(handler);
  }

  final image = Uint8List.fromList(<int>[1, 2, 3]);

  test('服务端 404（端点未实现）→ unavailable(server_error)', () async {
    final service = RemoteFoodRecognitionStub(
      dio: dioWith(
        (options) async => ResponseBody.fromString(
          '{"code":"NOT_FOUND"}',
          404,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      ),
    );
    final outcome = await service.recognize(image);
    expect(outcome, isA<RecognitionUnavailable>());
    expect((outcome as RecognitionUnavailable).reason, 'server_error');
  });

  test('网络不可达 → unavailable(network)', () async {
    final service = RemoteFoodRecognitionStub(
      dio: dioWith(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    final outcome = await service.recognize(image);
    expect((outcome as RecognitionUnavailable).reason, 'network');
  });

  test('即使意外 2xx 也不伪造候选 → unavailable(not_integrated)', () async {
    final service = RemoteFoodRecognitionStub(
      dio: dioWith(
        (options) async => ResponseBody.fromString(
          '{"data":{}}',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      ),
    );
    final outcome = await service.recognize(image);
    expect((outcome as RecognitionUnavailable).reason, 'not_integrated');
  });
}

final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
