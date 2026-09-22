import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/data/remote_exercise_log_sync.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';

/// 运动记录两态同步（手动记运动/截图导入上行，2026-09-19 拍板）：
/// 入账 pending → /sync/push 上行回填；删除 tombstone 上行 delete；
/// /sync/pull exerciseLogChanges 下行入库（跨端合并）。
void main() {
  late FakeHttpAdapter adapter;
  late RemoteExerciseLogSync exerciseSync;
  late RemoteRecordSync recordSync;
  late AppDatabase db;
  late ExerciseLogRepository repo;

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    exerciseSync = RemoteExerciseLogSync(dio: dio);
    recordSync = RemoteRecordSync(dio: dio, location: tz.UTC);
    db = AppDatabase.memory();
    repo = ExerciseLogRepository(
      db: db,
      clock: () => DateTime.utc(2026, 9, 19, 2),
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

  group('入账与删除队列（两态 pending/synced）', () {
    test('入账落 pending 并生成幂等键', () async {
      final log = await repo.add(
        typeKey: 'walk',
        durationMin: 0,
        kcal: 68,
        steps: 1466,
      );
      expect(log.syncState, ExerciseSyncState.pending);
      expect(log.clientRequestId, isNotEmpty);
      expect(log.serverId, isNull);
      final pending = await db.exerciseLogDao.pendingForUser('anonymous');
      expect(pending.map((e) => e.localId), <String>[log.localId]);
    });

    test('删除从未上行的记录：物理删除，队列清空', () async {
      final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      expect(await repo.delete(log.localId), isTrue);
      expect(await db.exerciseLogDao.getByLocalId(log.localId), isNull);
      expect(await db.exerciseLogDao.pendingForUser('anonymous'), isEmpty);
    });

    test('删除已同步记录：置 tombstone 保持 pending，合计即时排除', () async {
      final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      await db.exerciseLogDao.markSynced(log.localId, 'srv-e1');
      expect(await repo.totalKcalForDate('2026-09-19'), 210);

      expect(await repo.delete(log.localId), isTrue);
      final stored = (await db.exerciseLogDao.getByLocalId(log.localId))!;
      expect(stored.deleted, isTrue);
      expect(stored.syncState, ExerciseSyncState.pending);
      // 聚合即时排除（撤销即时生效）。
      expect(await repo.totalKcalForDate('2026-09-19'), 0);
      // tombstone 仍在 pending 队列（待上行 delete op）。
      expect(await db.exerciseLogDao.pendingForUser('anonymous'), hasLength(1));
    });
  });

  group('上行 pushPending（/sync/push entity=exerciseLog）', () {
    test('create applied → 回填 serverId 转 synced，出队；op 载荷完整', () async {
      final log = await repo.add(
        typeKey: 'walk',
        durationMin: 0,
        kcal: 68,
        steps: 1466,
        source: ExerciseLogRepository.sourceScreenshot,
      );
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'applied',
          'serverEntry': <String, dynamic>{'id': 'srv-e1', 'version': 1},
        },
      ]);

      await exerciseSync.pushPending(db, 'anonymous');

      final stored = (await db.exerciseLogDao.getByLocalId(log.localId))!;
      expect(stored.syncState, ExerciseSyncState.synced);
      expect(stored.serverId, 'srv-e1');
      expect(await db.exerciseLogDao.pendingForUser('anonymous'), isEmpty);
      final op = pushOp(0, 0);
      expect(op['entity'], 'exerciseLog');
      expect(op['op'], 'create');
      expect(op['clientRequestId'], log.clientRequestId);
      final payload = op['payload']! as Map<dynamic, dynamic>;
      expect(payload['typeKey'], 'walk');
      expect(payload['durationMin'], 0);
      expect(payload['kcal'], 68);
      expect(payload['steps'], 1466);
      expect(payload['source'], 'screenshot');
      expect(payload['loggedAt'], '2026-09-19T02:00:00.000Z');
      expect(payload['localDate'], '2026-09-19');
    });

    test('网络错误：整批保持 pending，离线状态翻转', () async {
      await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      adapter.stub('/sync/push', StubResponse.networkError('boom'));

      await exerciseSync.pushPending(db, 'anonymous');

      expect(await db.exerciseLogDao.pendingForUser('anonymous'), hasLength(1));
      expect(exerciseSync.isOnline, isFalse);
    });

    test('tombstone 上行 delete applied → 本地物理清除', () async {
      final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      await db.exerciseLogDao.markSynced(log.localId, 'srv-e1');
      await repo.delete(log.localId); // tombstone
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'applied',
        },
      ]);

      await exerciseSync.pushPending(db, 'anonymous');

      expect(await db.exerciseLogDao.getByLocalId(log.localId), isNull);
      final op = pushOp(0, 0);
      expect(op['op'], 'delete');
      expect(op['serverId'], 'srv-e1');
      expect(
        (op['payload']! as Map<dynamic, dynamic>)['clientRequestId'],
        log.clientRequestId,
      );
    });

    test('tombstone 上行 NOT_FOUND（服务端本无此行）→ 本地清除', () async {
      final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      await db.exerciseLogDao.markSynced(log.localId, 'srv-e1');
      await repo.delete(log.localId);
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'error',
          'error': <String, dynamic>{'code': 'NOT_FOUND'},
        },
      ]);

      await exerciseSync.pushPending(db, 'anonymous');

      expect(await db.exerciseLogDao.getByLocalId(log.localId), isNull);
    });

    test('create 被 VALIDATION_ERROR 永久拒绝 → 本地清除不再重试', () async {
      // 步数超服务端 200000 硬上限等硬边界校验＝永久拒绝；保留 pending 会
      // 每轮 syncNow 重复上行永不归零（走查 L4），必须本地清出。
      final log = await repo.add(
        typeKey: 'walk',
        durationMin: 30,
        kcal: 120,
        steps: 300000,
      );
      stubPush(<Map<String, dynamic>>[
        <String, dynamic>{
          'clientRequestId': log.clientRequestId,
          'status': 'error',
          'error': <String, dynamic>{'code': 'VALIDATION_ERROR'},
        },
      ]);

      await exerciseSync.pushPending(db, 'anonymous');

      expect(await db.exerciseLogDao.getByLocalId(log.localId), isNull);
      expect(await db.exerciseLogDao.pendingForUser('anonymous'), isEmpty);
    });
  });

  group('下行 exerciseLogChanges（/sync/pull 随行，跨端合并）', () {
    void stubPull(Map<String, dynamic> body) {
      adapter.stub(
        '/sync/pull',
        StubResponse.json(200, StubResponse.envelope(body)),
      );
    }

    test('A 机上行 → B 机全量下行入库为 synced（跨端可见）；tombstone 清除', () async {
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'exerciseLogChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'exerciseLog',
            'id': 'srv-e1',
            'clientRequestId': 'c-1',
            'typeKey': 'walk',
            'durationMin': 0,
            'kcal': 68,
            'steps': 1466,
            'source': 'screenshot',
            'loggedAt': '2026-09-19T02:00:00.000Z',
            'localDate': '2026-09-19',
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'u-A', null);

      final stored = await db.exerciseLogDao.getByServerId('srv-e1');
      expect(stored, isNotNull);
      expect(stored!.typeKey, 'walk');
      expect(stored.steps, 1466);
      expect(stored.kcal, 68);
      expect(stored.source, 'screenshot');
      expect(stored.syncState, ExerciseSyncState.synced);
      expect(stored.userId, 'u-A');

      // tombstone 下行 → 清除已同步行。
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'exerciseLogChanges': <dynamic>[
          <String, dynamic>{
            'tombstone': <String, dynamic>{
              'entity': 'exerciseLog',
              'id': 'srv-e1',
              'deletedAt': '2026-09-19T03:00:00.000Z',
            },
          },
        ],
        'syncToken': 'st_2',
        'hasMore': false,
      });
      await recordSync.pullDown(db, 'u-A', 'st_1');
      expect(await db.exerciseLogDao.getByServerId('srv-e1'), isNull);
    });

    test('本地 pending 行不被下行覆盖（幂等键对账后由上行回填）', () async {
      final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
      stubPull(<String, dynamic>{
        'changes': const <dynamic>[],
        'exerciseLogChanges': <dynamic>[
          <String, dynamic>{
            'entity': 'exerciseLog',
            'id': 'srv-e9',
            'clientRequestId': log.clientRequestId,
            'typeKey': 'jog',
            'durationMin': 30,
            'kcal': 210,
            'loggedAt': '2026-09-19T02:00:00.000Z',
            'localDate': '2026-09-19',
            'version': 1,
          },
        ],
        'syncToken': 'st_1',
        'hasMore': false,
      });

      await recordSync.pullDown(db, 'anonymous', null);

      final stored = (await db.exerciseLogDao.getByLocalId(log.localId))!;
      expect(stored.syncState, ExerciseSyncState.pending); // 未被覆盖
      expect(stored.serverId, isNull);
    });
  });
}
