import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_dao.dart';
import 'package:eatwise/features/record/data/food_search_remote.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Gate {
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() async {
    started.complete();
    await release.future;
  }
}

final class _Database extends AppDatabase {
  _Database() : super(NativeDatabase.memory());
  late final _FoodDao delayedFoods = _FoodDao(this);
  @override
  FoodDao get foodDao => delayedFoods;
}

final class _FoodDao extends FoodDao {
  _FoodDao(super.db);
  _Gate? localSearch;
  _Gate? cacheRead;

  @override
  Future<List<Food>> searchFoods(
    String query, {
    int limit = 20,
    String ownerUserId = 'anonymous',
  }) async {
    final rows = await super.searchFoods(
      query,
      limit: limit,
      ownerUserId: ownerUserId,
    );
    final gate = localSearch;
    localSearch = null;
    if (gate != null) await gate.wait();
    return rows;
  }

  @override
  Future<Food?> getById(String id, {String? ownerUserId}) async {
    final row = await super.getById(id, ownerUserId: ownerUserId);
    final gate = cacheRead;
    cacheRead = null;
    if (gate != null) await gate.wait();
    return row;
  }
}

final class _Adapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': 'private-food',
            'nameZh': '私人食品',
            'nameEn': 'Private food',
            'source': 'manual',
            'isCustom': true,
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Database db;
  late InMemoryTokenStore tokens;
  late Dio dio;
  late _Adapter adapter;
  late RemoteFoodSearch search;

  Future<void> login(String uid) => tokens.saveTokens(
    accessToken: 'access-$uid',
    refreshToken: 'refresh-$uid',
    userId: uid,
  );

  setUp(() async {
    db = _Database();
    tokens = InMemoryTokenStore();
    await login('user-a');
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'))
      ..httpClientAdapter = adapter;
    dio.options.extra[sessionTokenStoreKey] = tokens;
    dio.interceptors.add(
      AuthInterceptor(
        tokenStore: tokens,
        refreshDio: Dio(),
        apiBaseUrl: 'https://api.example.test/v1',
      )..dio = dio,
    );
    search = RemoteFoodSearch(dio: dio, db: db, userId: 'user-a');
  });
  tearDown(() async {
    dio.close();
    await db.close();
  });

  test(
    'account switch during local search cannot request or cache as new user',
    () async {
      final gate = _Gate();
      db.delayedFoods.localSearch = gate;
      final result = search.search('food');
      final assertion = expectLater(
        result,
        throwsA(isA<SessionChangedException>()),
      );
      await gate.started.future;
      await login('user-b');
      gate.release.complete();
      await assertion;
      expect(adapter.calls, 0);
      expect(await db.foodDao.getById('private-food'), isNull);
    },
  );

  for (final nextUser in ['user-b', 'user-a']) {
    test(
      'session replacement by $nextUser after HTTP response rolls back cache',
      () async {
        final gate = _Gate();
        db.delayedFoods.cacheRead = gate;
        final result = search.search('food');
        final assertion = expectLater(
          result,
          throwsA(isA<SessionChangedException>()),
        );
        await gate.started.future;
        await login(nextUser);
        gate.release.complete();
        await assertion;
        expect(adapter.calls, 1);
        expect(await db.foodDao.getById('private-food'), isNull);
      },
    );
  }

  test('current session still caches private result with its owner', () async {
    final hits = await search.search('food');
    expect(hits.single.ownerUserId, 'user-a');
    expect((await db.foodDao.getById('private-food'))!.ownerUserId, 'user-a');
  });
}
