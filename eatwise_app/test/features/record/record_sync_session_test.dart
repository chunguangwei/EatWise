import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/water_log_dao.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/auth_session_race_test.dart'
    show DelayedSessionAdapter;
import '../../core/network/fake_http_adapter.dart';

class _DelayedPlan extends FastingPlanSync {
  _DelayedPlan(SharedPreferences prefs)
    : super(api: FastingPlanApi(Dio()), prefs: prefs, userId: () => 'A');

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> flush() async {}

  @override
  Future<void> pull() async {
    started.complete();
    await release.future;
  }
}

class _DelayedWaterDatabase extends AppDatabase {
  _DelayedWaterDatabase() : super(NativeDatabase.memory());

  final inserted = Completer<void>();
  final release = Completer<void>();

  late final WaterLogDao _delayedWaterDao = _DelayedWaterDao(this);

  @override
  WaterLogDao get waterLogDao => _delayedWaterDao;
}

class _DelayedWaterDao extends WaterLogDao {
  _DelayedWaterDao(this.database) : super(database);
  final _DelayedWaterDatabase database;

  @override
  Future<void> insertLog(WaterLogsCompanion log) async {
    await super.insertLog(log);
    database.inserted.complete();
    await database.release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disposed repository stops an old sync after an awaited dependency',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokens = InMemoryTokenStore();
      await tokens.saveTokens(
        accessToken: 'A-token',
        refreshToken: 'A-refresh',
        userId: 'A',
      );
      final dio = createApiDio(tokenStore: tokens);
      final adapter = FakeHttpAdapter(
        fallback: StubResponse.json(
          200,
          StubResponse.envelope({
            'changes': <Map<String, dynamic>>[],
            'syncToken': 'B-cursor',
            'hasMore': false,
          }),
        ),
      );
      dio.httpClientAdapter = adapter;
      final db = AppDatabase.memory();
      final repository = RecordRepository(
        db: db,
        remote: RemoteRecordSync(dio: dio, location: tz.UTC),
        location: tz.UTC,
        userId: 'A',
      );
      addTearDown(() async {
        await repository.dispose();
        await db.close();
        dio.close(force: true);
      });
      final plan = _DelayedPlan(prefs);
      final engine = RecordSyncEngine(
        repository: repository,
        prefs: prefs,
        planSync: plan,
      );
      final syncing = engine.syncNow();
      await plan.started.future;
      await tokens.clear();
      await repository.dispose();
      await tokens.saveTokens(
        accessToken: 'B-token',
        refreshToken: 'B-refresh',
        userId: 'B',
      );
      plan.release.complete();
      await syncing;
      expect(adapter.requests, isEmpty);
      expect(prefs.getString('record_sync_token_A'), isNull);
    },
  );

  test(
    'late pull response cannot write old rows or advance its cursor after logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokens = InMemoryTokenStore();
      await tokens.saveTokens(
        accessToken: 'A-token',
        refreshToken: 'A-refresh',
        userId: 'A',
      );
      final dio = createApiDio(tokenStore: tokens);
      final adapter = DelayedSessionAdapter(
        delayPath: '/sync/pull',
        delayed: StubResponse.json(
          200,
          StubResponse.envelope({
            'changes': <Map<String, dynamic>>[],
            'waterLogChanges': [
              {
                'id': 'water-A',
                'clientRequestId': 'water-request-A',
                'amountMl': 250,
                'loggedAt': '2026-10-25T04:00:00.000Z',
                'createdAt': '2026-10-25T04:00:00.000Z',
              },
            ],
            'syncToken': 'A-cursor',
            'hasMore': false,
          }),
        ),
      );
      dio.httpClientAdapter = adapter;
      final db = AppDatabase.memory();
      final repository = RecordRepository(
        db: db,
        remote: RemoteRecordSync(dio: dio, location: tz.UTC),
        location: tz.UTC,
        userId: 'A',
      );
      addTearDown(() async {
        await repository.dispose();
        await db.close();
        dio.close(force: true);
      });
      final engine = RecordSyncEngine(repository: repository, prefs: prefs);
      final syncing = engine.syncNow();
      await adapter.started.future;
      await tokens.clear();
      await repository.dispose();
      await tokens.saveTokens(
        accessToken: 'B-token',
        refreshToken: 'B-refresh',
        userId: 'B',
      );
      adapter.release.complete();
      await syncing;
      expect(await db.select(db.waterLogs).get(), isEmpty);
      expect(prefs.getString('record_sync_token_A'), isNull);
    },
  );

  test('logout during a DAO await rolls back the complete pull page', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tokens = InMemoryTokenStore();
    await tokens.saveTokens(accessToken: 'A', refreshToken: 'A-r', userId: 'A');
    final dio = createApiDio(tokenStore: tokens);
    final adapter = FakeHttpAdapter(
      fallback: StubResponse.json(
        200,
        StubResponse.envelope({
          'changes': <Map<String, dynamic>>[],
          'waterLogChanges': [
            {
              'id': 'water-A',
              'clientRequestId': 'water-request-A',
              'amountMl': 250,
              'loggedAt': '2026-10-25T04:00:00.000Z',
            },
          ],
          'syncToken': 'A-page',
          'hasMore': false,
        }),
      ),
    );
    dio.httpClientAdapter = adapter;
    final db = _DelayedWaterDatabase();
    final repository = RecordRepository(
      db: db,
      remote: RemoteRecordSync(dio: dio, location: tz.UTC),
      location: tz.UTC,
      userId: 'A',
    );
    addTearDown(() async {
      await repository.dispose();
      await db.close();
      dio.close(force: true);
    });
    final engine = RecordSyncEngine(repository: repository, prefs: prefs);
    final syncing = engine.syncNow();
    await db.inserted.future;
    await tokens.clear();
    await tokens.saveTokens(accessToken: 'B', refreshToken: 'B-r', userId: 'B');
    db.release.complete();
    await syncing;
    expect(await db.select(db.waterLogs).get(), isEmpty);
    expect(prefs.getString('record_sync_token_A'), isNull);
  });

  test(
    'a direct remote call rejects a pending owner different from the token owner',
    () async {
      final tokens = InMemoryTokenStore();
      await tokens.saveTokens(
        accessToken: 'B',
        refreshToken: 'B-r',
        userId: 'B',
      );
      final dio = createApiDio(tokenStore: tokens);
      final adapter = FakeHttpAdapter();
      dio.httpClientAdapter = adapter;
      final db = AppDatabase.memory();
      addTearDown(() async {
        await db.close();
        dio.close(force: true);
      });
      await expectLater(
        RemoteWaterLogSync(dio: dio).pushPending(db, 'A'),
        throwsA(isA<SessionChangedException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
}
