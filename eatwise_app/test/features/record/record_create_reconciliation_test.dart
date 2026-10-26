import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/daily_nutrition_cache_repair.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

const user = 'review-user';
const day = '2026-10-25';
final now = DateTime.utc(2026, 10, 25, 4);

RecordDraft draft() => RecordDraft(
  foodId: 'f-rice',
  amountG: 100,
  mealUtc: now,
  source: EntrySource.manual,
);

Future<AppDatabase> database() async {
  final db = AppDatabase.memory();
  await db.foodDao.upsertAll([
    const FoodsCompanion(
      id: Value('f-rice'),
      nameZh: Value('白米饭'),
      nameEn: Value('White Rice'),
      kcalPer100g: Value(116),
      proteinPer100g: Value(2.6),
      carbPer100g: Value(25.9),
      fatPer100g: Value(0.3),
    ),
  ]);
  return db;
}

RecordRepository repository(AppDatabase db, RemoteRecordSync remote) =>
    RecordRepository(
      db: db,
      remote: remote,
      location: tz.UTC,
      userId: user,
      clock: () => now,
      undoWindow: const Duration(hours: 1),
    );

// HTTP-boundary simulator: server creates are deduplicated only by the immutable
// clientRequestId and reject changed payloads, matching SyncService.applyCreate.
// Production RecordRepository, RemoteRecordSync and drift SQLite execute unchanged.
class _MemoryApi {
  final records = <String, Map<String, dynamic>>{};
  final ops = <Map<String, dynamic>>[];
  String? pauseNextOp;
  Completer<void>? started;
  Completer<void>? release;
  bool loseNextCreateResponse = false;

  void pause(String op) {
    pauseNextOp = op;
    started = Completer<void>();
    release = Completer<void>();
  }

  RemoteRecordSync remote({InMemoryTokenStore? tokenStore}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://review.invalid'));
    if (tokenStore != null) {
      dio.options.extra[sessionTokenStoreKey] = tokenStore;
    }
    dio.interceptors.add(InterceptorsWrapper(onRequest: handle));
    return RemoteRecordSync(dio: dio, location: tz.UTC);
  }

  void handle(RequestOptions request, RequestInterceptorHandler handler) async {
    if (request.path == '/sync/pull') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 200,
          data: {
            'changes': [
              for (final row in records.values)
                if (row['deletedAt'] != null)
                  {
                    'tombstone': {
                      'id': row['id'],
                      'deletedAt': row['deletedAt'],
                    },
                  }
                else
                  Map<String, dynamic>.of(row),
            ],
            'syncToken': 'review-token',
            'hasMore': false,
          },
        ),
      );
      return;
    }
    if (request.path != '/sync/push') {
      throw StateError('Unexpected request ${request.path}');
    }
    final op = Map<String, dynamic>.from(
      ((request.data as Map<String, dynamic>)['ops'] as List).single as Map,
    );
    ops.add(op);
    final key = op['clientRequestId'] as String;
    final payload = Map<String, dynamic>.from(op['payload'] as Map);
    Map<String, dynamic>? row;
    var status = 'applied';
    String? error;
    if (op['op'] == 'create') {
      row = records[key];
      if (row != null &&
          (row['grams'] != payload['grams'] ||
              row['foodId'] != payload['foodId'] ||
              row['eatenAt'] != payload['eatenAt'])) {
        status = 'error';
        error = 'IDEMPOTENCY_PAYLOAD_MISMATCH';
      } else {
        row ??= {
          'id': 'server-${records.length + 1}',
          'clientRequestId': key,
          'foodId': payload['foodId'],
          'grams': payload['grams'],
          'eatenAt': payload['eatenAt'],
          'inputMethod': payload['inputMethod'],
          'nutritionSnapshot': {
            'kcal': payload['snapshotKcal'],
            'proteinG': payload['snapshotProteinG'],
            'carbsG': payload['snapshotCarbG'],
            'fatG': payload['snapshotFatG'],
          },
          'version': 1,
          'updatedAt': now.toIso8601String(),
        };
        records[key] = row;
      }
    } else if (op['op'] == 'delete') {
      row = records.values.where((r) => r['id'] == op['serverId']).firstOrNull;
      if (row == null) {
        status = 'error';
        error = 'NOT_FOUND';
      } else {
        row['deletedAt'] = now.toIso8601String();
      }
    } else if (op['op'] == 'update') {
      row = records.values.where((r) => r['id'] == op['serverId']).firstOrNull;
      if (row == null) {
        status = 'error';
        error = 'NOT_FOUND';
      } else {
        row['grams'] = payload['grams'];
        row['foodId'] = payload['foodId'];
        row['nutritionSnapshot'] = {
          'kcal': payload['snapshotKcal'],
          'proteinG': payload['snapshotProteinG'],
          'carbsG': payload['snapshotCarbG'],
          'fatG': payload['snapshotFatG'],
        };
        row['version'] = (row['version'] as int) + 1;
      }
    } else {
      throw StateError('Unexpected operation ${op['op']}');
    }
    if (pauseNextOp == op['op']) {
      pauseNextOp = null;
      started!.complete();
      await release!.future;
    }
    if (op['op'] == 'create' && loseNextCreateResponse) {
      loseNextCreateResponse = false;
      handler.reject(
        DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 200,
        data: {
          'results': [
            {
              'clientRequestId': key,
              'status': status,
              if (error != null) 'error': {'code': error},
              if (row != null && op['op'] != 'delete')
                'serverEntry': Map<String, dynamic>.of(row),
            },
          ],
        },
      ),
    );
  }
}

void main() {
  test('首次 create 在途删除：即时隐藏并先重算，回包后删除云端记录', () async {
    final db = await database();
    final api = _MemoryApi()..pause('create');
    final remote = api.remote();
    final repo = repository(db, remote);
    Future<void>? uploading;
    try {
      final entry = await repo.addEntry(draft());
      uploading = repo.flushEntry(entry.localId);
      await api.started!.future;
      expect(await repo.deleteEntry(entry.localId), isTrue);
      expect(await repo.entriesForDate(now), isEmpty);
      expect((await db.foodEntryDao.getDailyNutrition(user, day))!.kcal, 0);
      api.release!.complete();
      await uploading;
      await repo.retryPending();
      await remote.pullDown(db, user, null);
      expect(await repo.entriesForDate(now), isEmpty);
      expect(api.ops.map((o) => o['op']), ['create', 'delete']);
    } finally {
      if (!api.release!.isCompleted) api.release!.complete();
      if (uploading != null) await uploading;
      await repo.dispose();
      await db.close();
    }
  });

  for (final delete in [false, true]) {
    test('create 响应丢失后${delete ? '删除' : '编辑'}并重启：重放原请求后应用最新意图', () async {
      final db = await database();
      final api = _MemoryApi()..loseNextCreateResponse = true;
      final remote = api.remote();
      final repo = repository(db, remote);
      final dir = await Directory.systemTemp.createTemp(
        'eatwise-create-restart-',
      );
      try {
        final entry = await repo.addEntry(draft());
        await repo.flushEntry(entry.localId);
        final pending = (await db.foodEntryDao.getByLocalId(entry.localId))!;
        expect(pending.serverId, isNull);
        expect(pending.syncStatus, SyncStatus.pending);
        if (delete) {
          expect(await repo.deleteEntry(entry.localId), isTrue);
        } else {
          await repo.updateEntry(entry.localId, amountG: 200);
        }
        // SQLite snapshot is a process-interruption boundary, not an in-memory lock.
        final file = File('${dir.path}/interrupted.db');
        await db.customStatement('VACUUM INTO ?', [file.path]);
        final restoredDb = AppDatabase(NativeDatabase(file));
        final restoredRemote = api.remote();
        final restored = repository(restoredDb, restoredRemote);
        try {
          await restored.retryPending();
          await restoredRemote.pullDown(restoredDb, user, null);
          final rows = await restored.entriesForDate(now);
          expect(rows, hasLength(delete ? 0 : 1));
          if (!delete) expect(rows.single.amountG, 200);
          final cache = (await restoredDb.foodEntryDao.getDailyNutrition(
            user,
            day,
          ))!;
          expect(cache.kcal, delete ? 0 : 232);
          expect(api.ops.map((o) => o['op']), [
            'create',
            'create',
            delete ? 'delete' : 'update',
          ]);
          expect(api.ops[1]['clientRequestId'], api.ops[0]['clientRequestId']);
          expect(api.ops[1]['payload'], api.ops[0]['payload']);
          expect(api.records, hasLength(1));
        } finally {
          await restored.dispose();
          await restoredDb.close();
        }
      } finally {
        await repo.dispose();
        await db.close();
        await dir.delete(recursive: true);
      }
    });
  }

  for (final delete in [false, true]) {
    test('旧版同键载荷已改${delete ? '且已删除' : ''}：mismatch 保留意图，经下行关联后收敛', () async {
      final db = await database();
      final api = _MemoryApi()..loseNextCreateResponse = true;
      final remote = api.remote();
      final repo = repository(db, remote);
      try {
        final entry = await repo.addEntry(draft());
        await repo.flushEntry(entry.localId);
        final originalKey = entry.clientRequestId;
        await repo.updateEntry(entry.localId, amountG: 200);
        final changed = (await db.foodEntryDao.getByLocalId(entry.localId))!;
        // v15 没保存原请求；升级只能冻结当前 200g，云端原 create 是 100g。
        await db.foodEntryDao.updateEntry(
          entry.localId,
          FoodEntriesCompanion(
            clientRequestId: Value(originalKey),
            createRequestSnapshot: Value(
              jsonEncode(
                changed
                    .copyWith(
                      clientRequestId: originalKey,
                      createRequestSnapshot: const Value(null),
                    )
                    .toJson(),
              ),
            ),
          ),
        );
        if (delete) await repo.deleteEntry(entry.localId);
        await repo.retryPending();
        final waiting = (await db.foodEntryDao.getByLocalId(entry.localId))!;
        expect(waiting.lastError, 'IDEMPOTENCY_PAYLOAD_MISMATCH');
        expect(waiting.deleted, delete);
        expect(waiting.amountG, 200);
        await remote.pullDown(db, user, null);
        await repo.retryPending();
        await remote.pullDown(db, user, null);
        final rows = await repo.entriesForDate(now);
        expect(rows, hasLength(delete ? 0 : 1));
        if (!delete) expect(rows.single.amountG, 200);
        expect(
          (await db.foodEntryDao.getDailyNutrition(user, day))!.kcal,
          delete ? 0 : 232,
        );
        expect(api.records, hasLength(1));
        expect(api.ops.last['op'], delete ? 'delete' : 'update');
      } finally {
        await repo.dispose();
        await db.close();
      }
    });
  }

  test('首次 create 在途退出会话：迟到 ack 不回写，新仓储重放原请求', () async {
    final db = await database();
    final api = _MemoryApi()..pause('create');
    final remote = api.remote();
    final repo = repository(db, remote);
    Future<void>? uploading;
    try {
      final entry = await repo.addEntry(draft());
      uploading = repo.flushEntry(entry.localId);
      await api.started!.future;
      await repo.dispose();
      api.release!.complete();
      await uploading;
      final retained = (await db.foodEntryDao.getByLocalId(entry.localId))!;
      expect(retained.serverId, isNull);
      expect(retained.createRequestSnapshot, isNotNull);
      expect(await repo.retryPending(), 0);
      final restarted = repository(db, api.remote());
      try {
        await restarted.retryPending();
        final restored = (await db.foodEntryDao.getByLocalId(entry.localId))!;
        expect(restored.syncStatus, SyncStatus.synced);
        expect(api.ops[1]['clientRequestId'], api.ops[0]['clientRequestId']);
        expect(api.records, hasLength(1));
      } finally {
        await restarted.dispose();
      }
    } finally {
      if (!api.release!.isCompleted) api.release!.complete();
      if (uploading != null) await uploading;
      await repo.dispose();
      await db.close();
    }
  });

  test('v16 匿名冻结请求注册迁移后使用新owner续传，原wire载荷不变', () async {
    final db = await database();
    final api = _MemoryApi();
    final tokens = InMemoryTokenStore();
    final remote = api.remote(tokenStore: tokens)..online = false;
    final anonymous = RecordRepository(
      db: db,
      remote: remote,
      location: tz.UTC,
      clock: () => now,
      userId: 'anonymous',
    );
    try {
      final entry = await anonymous.addEntry(draft());
      // v15→v16 对匿名未同步行也冻结当前请求，随后注册会认领这些记录。
      await db.foodEntryDao.updateEntry(
        entry.localId,
        FoodEntriesCompanion(
          createRequestSnapshot: Value(jsonEncode(entry.toJson())),
        ),
      );
      await anonymous.dispose();
      await db.foodEntryDao.reassignUser('anonymous', user);
      await tokens.saveTokens(
        accessToken: 'signed-in',
        refreshToken: 'refresh',
        userId: user,
      );
      final signedIn = repository(db, api.remote(tokenStore: tokens));
      try {
        await signedIn.retryPending();
        final uploaded = (await db.foodEntryDao.getByLocalId(entry.localId))!;
        expect(uploaded.syncStatus, SyncStatus.synced);
        expect(uploaded.userId, user);
        expect(uploaded.createRequestSnapshot, isNull);
        expect(api.ops, hasLength(1));
        expect(api.ops.single['clientRequestId'], entry.clientRequestId);
        expect((api.ops.single['payload'] as Map)['grams'], 100);
      } finally {
        await signedIn.dispose();
      }
    } finally {
      await anonymous.dispose();
      await db.close();
    }
  });

  test('同账号重新登录后旧仓储延迟任务不借用新令牌发送，新仓储可以续传', () async {
    final db = await database();
    final api = _MemoryApi();
    final tokens = InMemoryTokenStore();
    await tokens.saveTokens(
      accessToken: 'old',
      refreshToken: 'old-refresh',
      userId: user,
    );
    final repo = repository(db, api.remote(tokenStore: tokens));
    try {
      final entry = await repo.addEntry(draft());
      await tokens.saveTokens(
        accessToken: 'new',
        refreshToken: 'new-refresh',
        userId: user,
      );
      // 模拟 Provider dispose 尚未执行而旧 Timer 已开始调度的间隙。
      await repo.flushEntry(entry.localId);
      expect(api.ops, isEmpty);
      final reopened = repository(db, api.remote(tokenStore: tokens));
      try {
        await reopened.retryPending();
        expect(
          (await db.foodEntryDao.getByLocalId(entry.localId))!.syncStatus,
          SyncStatus.synced,
        );
        expect(api.ops, hasLength(1));
      } finally {
        await reopened.dispose();
      }
    } finally {
      await repo.dispose();
      await db.close();
    }
  });

  for (final checkPendingGate in [true, false]) {
    test(
      'v16 冻结自定义食物引用${checkPendingGate ? '等待食物先行后' : ''}remap：原请求对账后更新到服务端食物ID',
      () async {
        final db = await database();
        final api = _MemoryApi();
        final remote = api.remote()..online = false;
        final repo = repository(db, remote);
        const temporaryId = 'custom-pending';
        const serverFoodId = 'cf-saved';
        try {
          await db.foodDao.upsertAll([
            const FoodsCompanion(
              id: Value(temporaryId),
              nameZh: Value('临时食物'),
              nameEn: Value('Pending food'),
              kcalPer100g: Value(116),
              proteinPer100g: Value(2.6),
              carbPer100g: Value(25.9),
              fatPer100g: Value(0.3),
              isCustom: Value(true),
              ownerUserId: Value(user),
              customSyncPending: Value(true),
            ),
          ]);
          final entry = await repo.addEntry(
            RecordDraft(
              foodId: temporaryId,
              amountG: 100,
              mealUtc: now,
              source: EntrySource.manual,
            ),
          );
          await db.foodEntryDao.updateEntry(
            entry.localId,
            FoodEntriesCompanion(
              createRequestSnapshot: Value(jsonEncode(entry.toJson())),
            ),
          );
          remote.online = true;
          if (checkPendingGate) {
            await repo.retryPending();
            expect(api.ops, isEmpty);
          }
          await db.foodDao.upsertAll([
            const FoodsCompanion(
              id: Value(serverFoodId),
              nameZh: Value('已上传食物'),
              nameEn: Value('Saved food'),
              kcalPer100g: Value(116),
              proteinPer100g: Value(2.6),
              carbPer100g: Value(25.9),
              fatPer100g: Value(0.3),
              isCustom: Value(true),
              ownerUserId: Value(user),
              customSyncPending: Value(false),
            ),
          ]);
          await db.foodEntryDao.remapFoodId(temporaryId, serverFoodId);
          await repo.retryPending();
          await remote.pullDown(db, user, null);
          final stored = (await repo.entriesForDate(now)).single;
          expect(stored.foodId, serverFoodId);
          expect(stored.syncStatus, SyncStatus.synced);
          expect(api.ops.map((op) => op['op']), ['create', 'update']);
          expect((api.ops.first['payload'] as Map)['foodId'], temporaryId);
          expect((api.ops.last['payload'] as Map)['foodId'], serverFoodId);
          expect(api.records, hasLength(1));
        } finally {
          await repo.dispose();
          await db.close();
        }
      },
    );
  }

  test('delete 在途快照重启：重试、下行及缓存修复后总量保持为零', () async {
    final db = await database();
    final api = _MemoryApi();
    final repo = repository(db, api.remote());
    final dir = await Directory.systemTemp.createTemp(
      'eatwise-delete-snapshot-',
    );
    Future<bool>? deleting;
    try {
      final entry = await repo.addEntry(draft());
      await repo.flushEntry(entry.localId);
      api.pause('delete');
      deleting = repo.deleteEntry(entry.localId);
      await api.started!.future;
      expect(await repo.entriesForDate(now), isEmpty);
      final file = File('${dir.path}/interrupted.db');
      await db.customStatement('VACUUM INTO ?', [file.path]);
      final restoredDb = AppDatabase(NativeDatabase(file));
      final restoredRemote = api.remote();
      final restored = repository(restoredDb, restoredRemote);
      try {
        expect(await restored.retryPending(), 1);
        await restoredRemote.pullDown(restoredDb, user, null);
        final repair = DailyNutritionCacheRepair(
          db: restoredDb,
          clock: () => now,
        );
        await repair.repairAll(user);
        await repair.repairRecent(user);
        expect(await restored.entriesForDate(now), isEmpty);
        final cache = (await restoredDb.foodEntryDao.getDailyNutrition(
          user,
          day,
        ))!;
        expect(cache.entryCount, 0);
        expect(cache.kcal, 0);
      } finally {
        await restored.dispose();
        await restoredDb.close();
      }
    } finally {
      if (api.release != null && !api.release!.isCompleted) {
        api.release!.complete();
      }
      if (deleting != null) await deleting;
      await repo.dispose();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
