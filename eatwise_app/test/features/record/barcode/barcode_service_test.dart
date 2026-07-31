import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/barcode/data/barcode_food_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../record_test_helper.dart';

/// 可编排响应的 Dio 适配器（避免真实网络）。
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.status = 200,
    this.body = const <String, dynamic>{},
    this.error,
  });

  final int status;
  final Object body;
  final DioException? error;
  final List<String> requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    final e = error;
    if (e != null) throw e;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    addTearDown(() async {
      await db.close();
    });
  });

  RemoteBarcodeFoodService serviceWith(_FakeAdapter adapter) {
    return RemoteBarcodeFoodService(
      dio: Dio()..httpClientAdapter = adapter,
      db: db,
    );
  }

  Map<String, dynamic> hitBody() => <String, dynamic>{
    'id': 'off_7622210449283',
    'barcode': '7622210449283',
    'nameZh': '奥利奥原味夹心饼干',
    'nameEn': 'Oreo Original',
    'aliases': <dynamic>[],
    'kcalPer100g': 480,
    'proteinPer100g': 4.7,
    'carbsPer100g': 68.5,
    'fatPer100g': 20.4,
    'source': 'openfoodfacts',
    'isCustom': false,
  };

  test('命中 → BarcodeLookupHit，且合入本地 Foods 缓存（离线可搜）', () async {
    final adapter = _FakeAdapter(body: hitBody());
    final outcome = await serviceWith(adapter).lookup('7622210449283');

    expect(adapter.requestedPaths, <String>['/foods/barcode/7622210449283']);
    expect(outcome, isA<BarcodeLookupHit>());
    final food = (outcome as BarcodeLookupHit).food;
    expect(food.id, 'off_7622210449283');
    expect(food.nameZh, '奥利奥原味夹心饼干');
    expect(food.kcalPer100g, 480);
    // 已落本地缓存：本地搜索可见。
    final cached = await db.foodDao.getById('off_7622210449283');
    expect(cached, isNotNull);
    expect(cached!.nameEn, 'Oreo Original');
  });

  test('404 FOOD_BARCODE_NOT_FOUND → BarcodeLookupNotFound', () async {
    final adapter = _FakeAdapter(
      status: 404,
      body: <String, dynamic>{
        'error': <String, dynamic>{
          'code': 'FOOD_BARCODE_NOT_FOUND',
          'message': '未收录该商品',
        },
      },
    );
    final outcome = await serviceWith(adapter).lookup('0000000000000');
    expect(outcome, isA<BarcodeLookupNotFound>());
  });

  test('网络错误 → BarcodeLookupUnavailable（不误判未收录）', () async {
    final adapter = _FakeAdapter(
      error: DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ),
    );
    final outcome = await serviceWith(adapter).lookup('7622210449283');
    expect(outcome, isA<BarcodeLookupUnavailable>());
  });

  test('5xx → BarcodeLookupUnavailable', () async {
    final adapter = _FakeAdapter(
      status: 500,
      body: <String, dynamic>{
        'error': <String, dynamic>{
          'code': 'INTERNAL_ERROR',
          'message': '服务开小差了',
        },
      },
    );
    final outcome = await serviceWith(adapter).lookup('7622210449283');
    expect(outcome, isA<BarcodeLookupUnavailable>());
  });
}
