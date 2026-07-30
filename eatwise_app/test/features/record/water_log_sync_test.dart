import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/data/remote_water_log_sync.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';

/// 饮水两态同步（PRD M3 功能点 4）：入账 pending → /sync/push 上行回填；
/// 撤销 tombstone 上行 delete；/sync/pull waterLogChanges 下行入库。
void main() {
  late FakeHttpAdapter adapter;
  late RemoteWaterLogSync waterSync;
  late RemoteRecordSync recordSync;
  late AppDatabase db;
  late WaterLogRepository repo;

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    waterSync = RemoteWaterLogSync(dio: dio);
    recordSync = RemoteRecordSync(dio: dio, location: tz.UTC);
    db = AppDatabase.memory();
    repo = WaterLogRepository(
      db: db,
      clock: () => DateTime.utc(2026, 7, 29, 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

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

  Map<String, dynamic> pushOp(int requestIndex, int opIndex) {
    final body = adapter.requestBodies[requestIndex] as Map<dynamic, dynamic>;
    return ((body['ops']! as List<dynamic>)[opIndex]) as Map<String, dynamic>;
  }

  group('入账与撤销队列（两态 pending/synced）', () {
    test('入账落 pending 并生成幂等键', () async {
      final log = await repo.add(300);
      expect(log.syncState, WaterSyncState.pending);
      expect(log.clientRequestId, isNotEmpty);
      expect(log.serverId, isNull);
      final pending = await db.waterLogDao.pendingForUser('anonymous');
      expect(pending.map((e) => e.localId), <String>[log.localId]);
    });

    test('撤销从未上行的记录：物理删除，队列清空', () async {
      final log = await repo.add(200);
      expect(await repo.undo(log.localId), isTrue);
      expect(await db.waterLogDao.getByLocalId(log.localId), isNull);
      expect(await db.waterLogDao.pendingForUser('anonymous'), isEmpty);
    });

    test('撤销已同步记录：置 tombstone 保持 pending，累计即时排除', () async {
      final log = await repo.add(200);
      await db.waterLogDao.markSynced(log.localId, 'srv-w1');
      expect(await repo.totalForDate('2026-07-29'), 200);

      expect(await repo.undo(log.localId), isTrue);
      final stored = (await db.waterLogDao.getByLocalId(log.localId))!;
      expect(stored.deleted, isTrue);
      expect(stored.syncState, WaterSyncState.pending);
      // 聚合即时排除（撤销即时生效）。
      expect(await repo.totalForDate('2026-07-29'), 0);
    });
  });

  group('上行 pushPending（/sync/push entity=waterLog）', () {
    test('create applied → 回填 serverId 转 synced，出队', () async {
      final log = await repo.add(300);
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'applied',
          'serverEntry': <String, dynamic>{'id': 'srv-w1', 'version': 1},
        },
      ]);

      await waterSync.pushPending(db, 'anonymous');

      final stored = (await db.waterLogDao.getByLocalId(log.localId))!;
      expect(stored.syncState, WaterSyncState.synced);
      expect(stored.serverId, 'srv-w1');
      expect(await db.waterLogDao.pendingForUser('anonymous'), isEmpty);
      // op 结构：幂等键复用行 clientRequestId，载荷 amountMl/loggedAt/localDate。
      final op = pushOp(0, 0);
      expect(op['entity'], 'waterLog');
      expect(op['op'], 'create');
      expect(op['clientRequestId'], log.clientRequestId);
      final payload = op['payload']! as Map<dynamic, dynamic>;
      expect(payload['amountMl'], 300);
      expect(payload['loggedAt'], '2026-07-29T01:00:00.000Z');
      expect(payload['localDate'], '2026-07-29');
    });

    test('网络错误：整批保持 pending，离线状态翻转', () async {
      await repo.add(200);
      adapter.stub('/sync/push', StubResponse.networkError('boom'));

      await waterSync.pushPending(db, 'anonymous');

      expect(await db.waterLogDao.pendingForUser('anonymous'), hasLength(1));
      expect(waterSync.isOnline, isFalse);
    });

    test('tombstone 上行 delete applied → 本地物理清除', () async {
      final log = await repo.add(200);
      await db.waterLogDao.markSynced(log.localId, 'srv-w1');
      await repo.undo(log.localId); // tombstone
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'applied',
        },
      ]);

      await waterSync.pushPending(db, 'anonymous');

      expect(await db.waterLogDao.getByLocalId(log.localId), isNull);
      final op = pushOp(0, 0);
      expect(op['op'], 'delete');
      expect(op['serverId'], 'srv-w1');
      expect(
        (op['payload']! as Map<dynamic, dynamic>)['clientRequestId'],
        log.clientRequestId,
      );
    });

    test('tombstone 上行 NOT_FOUND（服务端本无此行）→ 本地清除', () async {
      final log = await repo.add(200);
      await db.waterLogDao.markSynced(log.localId, 'srv-w1');
      await repo.undo(log.localId);
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'error',
          'error': <String, dynamic>{'code': 'NOT_FOUND'},
        },
      ]);

      await waterSync.pushPending(db, 'anonymous');

      expect(await db.waterLogDao.getByLocalId(log.localId), isNull);
    });
  });

  group('下行 waterLogChanges（/sync/pull 随行）', () {
    void stubPull(Map<String, dynamic> body) {
      adapter.stub(
        '/sync/pull',
        StubResponse.json(200, StubResponse.envelope(body)),
      );
    }

    test('新行下行入库为 synced；tombstone 清除已同步行', () async {
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'waterLogChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'waterLog',
            'id': 'srv-w1',
            'clientRequestId': 'c-1',
            'amountMl': 500,
            'loggedAt': '2026-07-29T02:00:00.000Z',
            'localDate': '2026-07-29',
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'u-1', null);

      final stored = await db.waterLogDao.getByServerId('srv-w1');
      expect(stored, isNotNull);
      expect(stored!.amountMl, 500);
      expect(stored.syncState, WaterSyncState.synced);
      expect(stored.userId, 'u-1');

      // tombstone 下行 → 清除已同步行。
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'waterLogChanges': <dynamic>[
          <String, dynamic>{
            'tombstone': <String, dynamic>{
              'entity': 'waterLog',
              'id': 'srv-w1',
              'deletedAt': '2026-07-29T03:00:00.000Z',
            },
          },
        ],
        'syncToken': 'st_2',
        'hasMore': false,
      });
      await recordSync.pullDown(db, 'u-1', 'st_1');
      expect(await db.waterLogDao.getByServerId('srv-w1'), isNull);
    });

    test('本地 pending 行不被下行覆盖（幂等键对账后由上行回填）', () async {
      final log = await repo.add(300); // userId=anonymous, pending
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'waterLogChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'waterLog',
            'id': 'srv-w9',
            'clientRequestId': log.clientRequestId,
            'amountMl': 300,
            'loggedAt': '2026-07-29T01:00:00.000Z',
            'localDate': '2026-07-29',
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'anonymous', null);

      final stored = (await db.waterLogDao.getByLocalId(log.localId))!;
      expect(stored.syncState, WaterSyncState.pending); // 未被覆盖
      expect(stored.serverId, isNull);
    });
  });
}
