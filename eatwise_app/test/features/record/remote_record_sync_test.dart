import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';
import 'record_test_helper.dart';

void main() {
  late FakeHttpAdapter adapter;
  late RemoteRecordSync remote;
  late AppDatabase db;

  FoodEntry makeEntry({
    String localId = 'l-1',
    String clientRequestId = '11111111-1111-4111-8111-111111111111',
    String? serverId,
    int? serverVersion,
    SyncStatus syncStatus = SyncStatus.submitting,
    double amountG = 200,
  }) {
    return FoodEntry(
      localId: localId,
      userId: 'u-1',
      serverId: serverId,
      clientRequestId: clientRequestId,
      syncStatus: syncStatus,
      localVersion: 1,
      serverVersion: serverVersion,
      serverUpdatedAt: null,
      retryCount: 0,
      deleted: false,
      datetimeUtc: '2026-07-27T01:10:00.000Z',
      localDate: '2026-07-27',
      foodId: 'f-rice',
      amountG: amountG,
      kcal: 232,
      proteinG: 5.2,
      carbG: 51.8,
      fatG: 0.6,
      source: EntrySource.manual,
      duringFast: false,
      createdAtUtc: '2026-07-27T01:10:00.000Z',
      updatedAtUtc: '2026-07-27T01:10:00.000Z',
    );
  }

  Map<String, dynamic> pushResult({
    required String clientRequestId,
    String status = 'applied',
    String? serverId,
    int version = 1,
    String? errorCode,
  }) {
    return <String, dynamic>{
      'clientRequestId': clientRequestId,
      'status': status,
      if (status != 'error')
        'serverEntry': <String, dynamic>{
          'id': serverId ?? 'srv-1',
          'version': version,
          'updatedAt': '2026-07-27T01:30:00.000Z',
        },
      if (errorCode != null) 'error': <String, dynamic>{'code': errorCode},
    };
  }

  void stubPush(List<Map<String, dynamic>> results) {
    adapter.stub(
      '/sync/push',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'results': results,
          'syncToken': 'st_x',
        }),
      ),
    );
  }

  Map<String, dynamic>? lastPushOp(int index) {
    final body = adapter.requestBodies[index] as Map<dynamic, dynamic>;
    return (body['ops']! as List<dynamic>)[0] as Map<String, dynamic>?;
  }

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    remote = RemoteRecordSync(dio: dio, location: tz.UTC);
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('上行 push（/sync/push ops 协议）', () {
    test('create：无 serverId，applied → PushAck 回填', () async {
      final entry = makeEntry();
      stubPush(<Map<String, dynamic>>[
        pushResult(clientRequestId: entry.clientRequestId, serverId: 'srv-9'),
      ]);
      final outcome = await remote.push(entry);
      expect(outcome, isA<PushAck>());
      final ack = outcome as PushAck;
      expect(ack.serverId, 'srv-9');
      expect(ack.serverVersion, 1);
      expect(ack.serverUpdatedAtUtc, '2026-07-27T01:30:00.000Z');
      final op = lastPushOp(0)!;
      expect(op['op'], 'create');
      expect(op['entity'], 'foodEntry');
      expect(op.containsKey('serverId'), isFalse);
      final payload = op['payload']! as Map<dynamic, dynamic>;
      expect(payload['eatenAt'], '2026-07-27T01:10:00.000Z');
      expect(payload['foodId'], 'f-rice');
      expect(payload['grams'], 200);
      expect(payload['inputMethod'], 'manual');
    });

    test('update：携带 serverId + baseVersion（LWW 冲突检测）', () async {
      final entry = makeEntry(serverId: 'srv-9', serverVersion: 3);
      stubPush(<Map<String, dynamic>>[
        pushResult(clientRequestId: entry.clientRequestId, version: 4),
      ]);
      final outcome = await remote.push(entry);
      expect(outcome, isA<PushAck>());
      expect((outcome as PushAck).serverVersion, 4);
      final op = lastPushOp(0)!;
      expect(op['op'], 'update');
      expect(op['serverId'], 'srv-9');
      expect(op['baseVersion'], 3);
    });

    test('conflict → PushConflict（服务端版本/时间戳）', () async {
      final entry = makeEntry(serverId: 'srv-9', serverVersion: 3);
      stubPush(<Map<String, dynamic>>[
        pushResult(
          clientRequestId: entry.clientRequestId,
          status: 'conflict',
          version: 4,
        ),
      ]);
      final outcome = await remote.push(entry);
      expect(outcome, isA<PushConflict>());
      expect((outcome as PushConflict).serverVersion, 4);
    });

    test('error VALIDATION_ERROR → PushReject（T7 回滚语义）', () async {
      final entry = makeEntry();
      stubPush(<Map<String, dynamic>>[
        pushResult(
          clientRequestId: entry.clientRequestId,
          status: 'error',
          errorCode: 'VALIDATION_ERROR',
        ),
      ]);
      final outcome = await remote.push(entry);
      expect(outcome, isA<PushReject>());
      expect((outcome as PushReject).code, 'VALIDATION_ERROR');
    });

    test('error INTERNAL_ERROR → PushRetryable（T5 保数据）', () async {
      final entry = makeEntry();
      stubPush(<Map<String, dynamic>>[
        pushResult(
          clientRequestId: entry.clientRequestId,
          status: 'error',
          errorCode: 'INTERNAL_ERROR',
        ),
      ]);
      final outcome = await remote.push(entry);
      expect(outcome, isA<PushRetryable>());
    });

    test('网络错误 → PushRetryable(NETWORK_ERROR) 且翻转为离线', () async {
      adapter.stub('/sync/push', StubResponse.networkError('offline'));
      final outcome = await remote.push(makeEntry());
      expect(outcome, isA<PushRetryable>());
      expect((outcome as PushRetryable).code, 'NETWORK_ERROR');
      expect(remote.isOnline, isFalse);
    });

    test('5xx → PushRetryable；成功请求翻回在线', () async {
      adapter.stub(
        '/sync/push',
        StubResponse.json(
          500,
          StubResponse.errorEnvelope('INTERNAL_ERROR', '服务端错误'),
        ),
      );
      expect(await remote.push(makeEntry()), isA<PushRetryable>());
      stubPush(<Map<String, dynamic>>[
        pushResult(clientRequestId: makeEntry().clientRequestId),
      ]);
      await remote.push(makeEntry());
      expect(remote.isOnline, isTrue);
    });

    test('批量上行 ≤100/批，分批串行（205 条 → 100+100+5）', () async {
      final entries = List<FoodEntry>.generate(
        205,
        (i) => makeEntry(
          localId: 'l-$i',
          clientRequestId:
              '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}',
        ),
      );
      for (var batch = 0; batch < 3; batch++) {
        final start = batch * 100;
        final end = batch == 2 ? 205 : start + 100;
        stubPush(<Map<String, dynamic>>[
          for (var i = start; i < end; i++)
            pushResult(clientRequestId: entries[i].clientRequestId),
        ]);
      }
      final outcomes = await remote.pushBatch(entries);
      expect(outcomes, hasLength(205));
      expect(outcomes.every((o) => o is PushAck), isTrue);
      expect(adapter.requestsTo('/sync/push'), 3);
      // 各批 ops 条数 100/100/5。
      final sizes = adapter.requestBodies
          .map(
            (b) =>
                ((b as Map<dynamic, dynamic>)['ops']! as List<dynamic>).length,
          )
          .toList();
      expect(sizes, <int>[100, 100, 5]);
    });
  });

  group('下行 pullDown（syncToken 游标翻页）', () {
    Map<String, dynamic> entryView({
      String id = 'srv-1',
      String clientRequestId = 'c-1',
      String foodId = 'f-rice',
      double grams = 200,
    }) {
      return <String, dynamic>{
        'id': id,
        'clientRequestId': clientRequestId,
        'eatenAt': '2026-07-27T01:10:00.000Z',
        'foodId': foodId,
        'grams': grams,
        'inputMethod': 'manual',
        'nutritionSnapshot': <String, dynamic>{
          'kcal': 232,
          'proteinG': 5.2,
          'carbsG': 51.8,
          'fatG': 0.6,
        },
        'version': 1,
        'updatedAt': '2026-07-27T01:30:00.000Z',
      };
    }

    void stubPull(
      List<Map<String, dynamic>> changes, {
      String syncToken = 'st_1',
      bool hasMore = false,
    }) {
      adapter.stub(
        '/sync/pull',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'changes': changes,
            'syncToken': syncToken,
            'hasMore': hasMore,
          }),
        ),
      );
    }

    setUp(() async {
      await seedFoods(db);
    });

    test('翻页拉取直到 hasMore=false，落库为 synced，返回末页 token', () async {
      stubPull(<Map<String, dynamic>>[entryView()], hasMore: true);
      stubPull(<Map<String, dynamic>>[
        entryView(id: 'srv-2', clientRequestId: 'c-2'),
      ], syncToken: 'st_2');
      final token = await remote.pullDown(db, 'u-1', null);
      expect(token, 'st_2');
      expect(adapter.requestsTo('/sync/pull'), 2);
      final entries = await db.foodEntryDao.entriesForDate('u-1', '2026-07-27');
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.syncStatus == SyncStatus.synced), isTrue);
      expect(entries.first.serverId, isNotNull);
      expect(entries.first.serverVersion, 1);
      // 营养快照与服务端下发一致。
      expect(entries.first.kcal, 232);
    });

    test('本地 pending 记录（同 clientRequestId）不被下行覆盖', () async {
      final repo = await _insertLocalPending(db);
      stubPull(<Map<String, dynamic>>[
        entryView(id: 'srv-1', clientRequestId: repo, grams: 999),
      ]);
      await remote.pullDown(db, 'u-1', 'st_0');
      final local = await db.foodEntryDao.getByClientRequestId(repo);
      expect(local!.amountG, 200); // 本地值保留
      expect(local.syncStatus, SyncStatus.pending);
    });

    test('tombstone：已同步记录软删；本地有未同步修改则双份保留', () async {
      // 已 synced 的本地记录 → 软删。
      await _insertLocalPending(db);
      final syncedEntry = makeEntry(
        localId: 'l-synced',
        clientRequestId: 'c-synced',
        serverId: 'srv-del',
        serverVersion: 1,
        syncStatus: SyncStatus.synced,
      );
      await db.foodEntryDao.insertEntry(syncedEntry.toCompanion(true));
      stubPull(<Map<String, dynamic>>[
        <String, dynamic>{
          'tombstone': <String, dynamic>{
            'id': 'srv-del',
            'deletedAt': '2026-07-27T02:00:00.000Z',
          },
        },
        <String, dynamic>{
          'tombstone': <String, dynamic>{
            'id': 'srv-pending',
            'deletedAt': '2026-07-27T02:00:00.000Z',
          },
        },
      ]);
      await remote.pullDown(db, 'u-1', 'st_0');
      final synced = await db.foodEntryDao.getByLocalId('l-synced');
      expect(synced!.deleted, isTrue);
      // srv-pending 对应本地 pending 记录：双份保留不软删（D-20 删改冲突）。
      final pending = await db.foodEntryDao.getByLocalId('l-pending');
      expect(pending!.deleted, isFalse);
    });

    test('INVALID_SYNC_TOKEN → 丢弃旧 token 全量重拉', () async {
      adapter.stub(
        '/sync/pull',
        StubResponse.json(
          400,
          StubResponse.errorEnvelope('INVALID_SYNC_TOKEN', '同步游标已失效'),
        ),
      );
      stubPull(<Map<String, dynamic>>[entryView()], syncToken: 'st_new');
      final token = await remote.pullDown(db, 'u-1', 'st_expired');
      expect(token, 'st_new');
      expect(adapter.requestsTo('/sync/pull'), 2);
      // 第二次请求不带 syncToken（全量）。
      expect(
        adapter.requests[1].queryParameters.containsKey('syncToken'),
        isFalse,
      );
    });

    test('本地缺失食物的 change 跳过：token 不推进，食物库补齐后重拉落库', () async {
      // 一页两条：f-rice 已知可落库，f-unknown 本地食物库缺失被跳过。
      List<Map<String, dynamic>> page() => <Map<String, dynamic>>[
        entryView(),
        entryView(id: 'srv-2', clientRequestId: 'c-2', foodId: 'f-unknown'),
      ];
      stubPull(page(), syncToken: 'st_1');
      final token = await remote.pullDown(db, 'u-1', 'st_0');

      // 存在跳过：返回入参游标（调用方不持久化新 token），防 change 永丢。
      expect(token, 'st_0');
      var entries = await db.foodEntryDao.entriesForDate('u-1', '2026-07-27');
      expect(entries.map((e) => e.serverId), <String?>['srv-1']);

      // 食物库补齐后按旧游标重拉：同页重放幂等，跳过条目落库，token 推进。
      await db.foodDao.upsertAll(<FoodsCompanion>[
        const FoodsCompanion(
          id: Value('f-unknown'),
          nameZh: Value('新品食物'),
          nameEn: Value('New Food'),
          aliasesZh: Value('[]'),
          aliasesEn: Value('[]'),
          kcalPer100g: Value(100),
          proteinPer100g: Value(5),
          carbPer100g: Value(10),
          fatPer100g: Value(2),
        ),
      ]);
      stubPull(page(), syncToken: 'st_1');
      final token2 = await remote.pullDown(db, 'u-1', token);
      expect(token2, 'st_1');
      entries = await db.foodEntryDao.entriesForDate('u-1', '2026-07-27');
      expect(entries, hasLength(2));
      expect(
        entries.map((e) => e.serverId),
        containsAll(<String?>['srv-1', 'srv-2']),
      );
    });
  });
}

/// 插入一条本地 pending 记录（serverId=srv-pending），返回 clientRequestId。
Future<String> _insertLocalPending(AppDatabase db) async {
  const clientRequestId = 'c-pending';
  final entry = FoodEntry(
    localId: 'l-pending',
    userId: 'u-1',
    serverId: 'srv-pending',
    clientRequestId: clientRequestId,
    syncStatus: SyncStatus.pending,
    localVersion: 2,
    serverVersion: 1,
    serverUpdatedAt: '2026-07-27T01:00:00.000Z',
    retryCount: 1,
    deleted: false,
    datetimeUtc: '2026-07-27T01:10:00.000Z',
    localDate: '2026-07-27',
    foodId: 'f-rice',
    amountG: 200,
    kcal: 232,
    proteinG: 5.2,
    carbG: 51.8,
    fatG: 0.6,
    source: EntrySource.manual,
    duringFast: false,
    createdAtUtc: '2026-07-27T01:10:00.000Z',
    updatedAtUtc: '2026-07-27T01:20:00.000Z',
  );
  await db.foodEntryDao.insertEntry(entry.toCompanion(true));
  return clientRequestId;
}
