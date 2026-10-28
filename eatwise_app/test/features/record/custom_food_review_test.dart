import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/network/fake_http_adapter.dart';

const oldDraft = CustomFoodDraft(
  nameZh: '旧食品',
  aliasesZh: [],
  per100g: NutritionSnapshot(kcal: 100, proteinG: 5, carbG: 10, fatG: 2),
  source: CustomFoodSource.manual,
);
const newDraft = CustomFoodDraft(
  nameZh: '新食品',
  aliasesZh: [],
  per100g: NutritionSnapshot(kcal: 200, proteinG: 5, carbG: 10, fatG: 2),
  source: CustomFoodSource.manual,
);

class DiagnosticRemote implements CustomFoodRemote {
  bool offline = false, loseAck = false;
  BusinessApiException? patchError;
  Completer<void>? started, gate, patchStarted, patchGate;
  int activePatches = 0, maxActivePatches = 0, patchCalls = 0;
  final requests = <String, String>{};
  final ids = <String, String>{};
  final cloud = <String, CustomFoodDraft>{};
  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    if (offline) throw const NetworkApiException();
    final payload =
        '${draft.nameZh}|${draft.nameEn}|${draft.source}|${draft.per100g.kcal}';
    final previous = requests[clientRequestId];
    if (previous != null && previous != payload) {
      throw const BusinessApiException(
        httpStatus: 409,
        code: 'PAYLOAD_MISMATCH',
        message: 'payload mismatch',
      );
    }
    requests[clientRequestId] = payload;
    final id = ids.putIfAbsent(
      clientRequestId,
      () => 'server-${ids.length + 1}',
    );
    cloud.putIfAbsent(id, () => draft);
    started?.complete();
    started = null;
    if (gate != null) await gate!.future;
    if (loseAck) {
      loseAck = false;
      throw const TimeoutApiException();
    }
    return id;
  }

  @override
  Future<void> updateCustom(String id, CustomFoodDraft draft) async {
    if (offline) throw const NetworkApiException();
    if (!cloud.containsKey(id)) {
      throw const BusinessApiException(
        httpStatus: 404,
        code: 'NOT_FOUND',
        message: 'not found',
      );
    }
    patchCalls++;
    activePatches++;
    if (activePatches > maxActivePatches) maxActivePatches = activePatches;
    patchStarted?.complete();
    patchStarted = null;
    if (patchGate != null) await patchGate!.future;
    activePatches--;
    if (patchError != null) throw patchError!;
    cloud[id] = draft;
  }

  @override
  Future<int> deleteCustom(String id) async => throw UnimplementedError();
  @override
  Future<String> contribute(
    String id, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) async => throw UnimplementedError();
  @override
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  }) async => throw UnimplementedError();
  @override
  Future<String> submitCorrection(
    String id,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DiagnosticRemote remote;
  late CustomFoodRepository repo;
  setUp(() {
    db = AppDatabase.memory();
    remote = DiagnosticRemote();
    repo = CustomFoodRepository(
      db: db,
      remote: remote,
      userId: 'review-user',
      existingFoodIdsFn: (ids) async =>
          ids.where(remote.cloud.containsKey).toSet(),
    );
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> pullConfirmedIdentity(String key) async {
    final dio = createApiDio(config: ApiConfig());
    final adapter = FakeHttpAdapter();
    dio.httpClientAdapter = adapter;
    adapter.stub(
      '/sync/pull',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'changes': <dynamic>[],
          'customFoodChanges': [
            {
              'id': 'server-1',
              'clientRequestId': key,
              'nameZh': oldDraft.nameZh,
              'nameEn': oldDraft.nameZh,
              'kcalPer100g': 100,
              'proteinPer100g': 5,
              'carbsPer100g': 10,
              'fatPer100g': 2,
            },
          ],
          'syncToken': 'st_1',
          'hasMore': false,
        }),
      ),
    );
    final pull = RemoteRecordSync(dio: dio, location: tz.UTC);
    await pull.pullDown(db, 'review-user', 'st_0');
    dio.close();
  }

  test('旧创建回执不得将新编辑清为已同步', () async {
    remote.offline = true;
    final saved = await repo.save(oldDraft);
    remote.offline = false;
    final started = Completer<void>();
    final gate = Completer<void>();
    remote.started = started;
    remote.gate = gate;
    final retry = repo.retryPending();
    await started.future;
    await repo.update(saved.food, newDraft);
    gate.complete();
    await retry;
    final local = await db.foodDao.getById(
      'server-1',
      ownerUserId: 'review-user',
    );
    expect(
      local!.customSyncPending ||
          remote.cloud.values.single.nameZh == newDraft.nameZh,
      isTrue,
    );
  });
  test('创建回执丢失后编辑不得创建第二个云端食品', () async {
    remote.loseAck = true;
    final saved = await repo.save(oldDraft);
    await repo.update(saved.food, newDraft);
    await repo.retryPending();
    expect(remote.cloud.length, 1);
    expect(remote.cloud.values.single.nameZh, newDraft.nameZh);
  });
  test('已删除食品编辑404不得标为共享', () async {
    final saved = await repo.save(oldDraft);
    remote.cloud.remove(saved.food.id);
    Object? error;
    try {
      await repo.update(saved.food, newDraft);
    } on Object catch (e) {
      error = e;
    }
    final local = await db.foodDao.getById(
      saved.food.id,
      ownerUserId: 'review-user',
    );
    expect(local?.contributionStatus, isNot('approved'));
    expect(error, isA<BusinessApiException>());
    expect(local!.customSyncPending, isTrue);
    expect(local.nameZh, newDraft.nameZh);
  });
  test('离线编辑已确认食品在重建仓储后补传PATCH', () async {
    final saved = await repo.save(oldDraft);
    remote.offline = true;
    await repo.update(saved.food, newDraft);
    final pending = await db.foodDao.getById(
      saved.food.id,
      ownerUserId: 'review-user',
    );
    expect(pending!.customSyncPending, isTrue);
    remote.offline = false;
    repo = CustomFoodRepository(db: db, remote: remote, userId: 'review-user');
    await repo.retryPending();
    expect(remote.cloud.length, 1);
    expect(remote.cloud[saved.food.id]!.nameZh, newDraft.nameZh);
  });
  test('在途PATCH新编辑由同食品串行补传，旧ACK不能吞新值', () async {
    final saved = await repo.save(oldDraft);
    final started = Completer<void>();
    final gate = Completer<void>();
    remote.patchStarted = started;
    remote.patchGate = gate;
    final first = repo.update(saved.food, newDraft);
    await started.future;
    // A second repository uses the same database transport lock.
    final other = CustomFoodRepository(
      db: db,
      remote: remote,
      userId: 'review-user',
    );
    final second = await other.update(saved.food, oldDraft);
    expect(second.customSyncPending, isTrue);
    gate.complete();
    await first;
    final local = (await db.foodDao.getById(saved.food.id))!;
    expect(local.nameZh, oldDraft.nameZh);
    expect(local.customSyncPending, isFalse);
    expect(remote.cloud[saved.food.id]!.nameZh, oldDraft.nameZh);
    expect(remote.maxActivePatches, 1);
    expect(remote.patchCalls, 2);
  });

  test('create前已持久化原键和快照，服务端ID碰撞保留最新编辑与引用', () async {
    remote.offline = true;
    final saved = await repo.save(oldDraft);
    expect(saved.food.customCreateRequestSnapshot, isNotNull);
    remote.offline = false;
    remote.started = Completer<void>();
    remote.gate = Completer<void>();
    final started = remote.started!;
    final retry = repo.retryPending();
    await started.future;
    await repo.update(saved.food, newDraft);
    await db.foodDao.upsertAll([
      saved.food
          .toCompanion(false)
          .copyWith(
            id: const Value('server-1'),
            nameZh: const Value('下行旧名'),
            customSyncPending: const Value(false),
          ),
    ]);
    // A minimal persisted entry proves remap updates actual references.
    await db.customStatement(
      """
      INSERT INTO food_entries (local_id,user_id,client_request_id,sync_status,
        datetime_utc,local_date,food_id,amount_g,kcal,protein_g,carb_g,fat_g,
        source,created_at_utc,updated_at_utc)
      VALUES ('entry-1','review-user','entry-key','pending',
        '2026-10-28T00:00:00Z','2026-10-28',?,100,100,5,10,2,'manual',
        '2026-10-28T00:00:00Z','2026-10-28T00:00:00Z')
    """,
      [saved.food.id],
    );
    remote.gate!.complete();
    expect(await retry, 1);
    final local = (await db.foodDao.getById('server-1'))!;
    expect(local.nameZh, newDraft.nameZh);
    expect(local.customSyncPending, isFalse);
    expect(await db.foodDao.getById(saved.food.id), isNull);
    expect((await db.foodEntryDao.getByLocalId('entry-1'))!.foodId, 'server-1');
  });

  test('丢ACK后真正关闭重开SQLite仍复用原create并PATCH最新值', () async {
    final dir = await Directory.systemTemp.createTemp('custom-food-restart-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    repo = CustomFoodRepository(db: db, remote: remote, userId: 'review-user');
    remote.loseAck = true;
    final saved = await repo.save(oldDraft);
    final key = saved.food.customClientRequestId;
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    repo = CustomFoodRepository(db: db, remote: remote, userId: 'review-user');
    final restored = (await db.foodDao.getById(saved.food.id))!;
    await repo.update(restored, newDraft);
    expect(
      (await db.foodDao.getById(saved.food.id))!.customClientRequestId,
      key,
    );
    expect(await repo.retryPending(), 1);
    expect(remote.cloud.length, 1);
    expect(remote.cloud.values.single.nameZh, newDraft.nameZh);
    expect(remote.requests.keys.single, key);
  });

  test('已删除404停止自动重试但保留手动恢复草稿', () async {
    final saved = await repo.save(oldDraft);
    remote.cloud.remove(saved.food.id);
    await expectLater(
      repo.update(saved.food, newDraft),
      throwsA(isA<BusinessApiException>()),
    );
    final failed = (await db.foodDao.getById(saved.food.id))!;
    expect(failed.customSyncFailed, isTrue);
    expect(await repo.retryPending(), 0);
    expect((await db.foodDao.getById(saved.food.id))!.nameZh, newDraft.nameZh);
    // Restoring server visibility makes the explicit retry recover this draft.
    remote.cloud[saved.food.id] = oldDraft;
    expect(await repo.retryFailedNow(saved.food.id), isTrue);
    expect(remote.cloud[saved.food.id]!.nameZh, newDraft.nameZh);
  });
  test('旧PATCH永久失败不累计到在途产生的新编辑代际', () async {
    final saved = await repo.save(oldDraft);
    remote.patchStarted = Completer<void>();
    remote.patchGate = Completer<void>();
    remote.patchError = const BusinessApiException(
      httpStatus: 422,
      code: 'VALIDATION_ERROR',
      message: 'old failure',
    );
    final started = remote.patchStarted!;
    final first = repo.update(saved.food, newDraft);
    final rejected = expectLater(first, throwsA(isA<BusinessApiException>()));
    await started.future;
    await repo.update(saved.food, oldDraft);
    remote.patchGate!.complete();
    await rejected;
    final latest = (await db.foodDao.getById(saved.food.id))!;
    expect(latest.customSyncPending, isTrue);
    expect(latest.customSyncFailCount, 0);
    expect(latest.customSyncFailed, isFalse);
    remote.patchError = null;
    expect(await repo.retryPending(), 1);
    expect(remote.cloud[saved.food.id]!.nameZh, oldDraft.nameZh);
  });
  for (final loseAck in [false, true]) {
    test('服务端下行精确绑定在途create，晚${loseAck ? '丢' : '成功'}ACK与ID碰撞不吞新编辑', () async {
      remote.started = Completer<void>();
      remote.gate = Completer<void>();
      remote.loseAck = loseAck;
      final started = remote.started!;
      final saving = repo.save(oldDraft);
      await started.future;
      final original = (await db.foodDao.pendingCustomFoods(
        ownerUserId: 'review-user',
      )).single;
      expect(original.customCreateRequestSnapshot, isNotNull);
      await repo.update(original, newDraft);
      await db.foodDao.upsertAll([
        original
            .toCompanion(false)
            .copyWith(
              id: const Value('server-1'),
              customSyncPending: const Value(false),
              customClientRequestId: const Value(''),
              customOriginLocalId: const Value(null),
            ),
      ]);
      await pullConfirmedIdentity(original.customClientRequestId);
      final bound = (await db.foodDao.getById('server-1'))!;
      expect(bound.customOriginLocalId, original.id);
      expect(bound.customClientRequestId, isEmpty);
      expect(bound.nameZh, newDraft.nameZh);
      expect(bound.customSyncPending, isTrue);
      // Editing through a stale local identity still reaches this same food.
      await repo.update(original, newDraft);
      remote.gate!.complete();
      final saved = await saving;
      expect(saved.food.id, 'server-1');
      expect(saved.uploaded, isTrue);
      expect(remote.cloud.length, 1);
      expect(remote.cloud.values.single.nameZh, newDraft.nameZh);
      expect(remote.maxActivePatches, 1);
      expect((await db.foodDao.allFoods(ownerUserId: 'review-user')).length, 1);
    });
  }

  test('旧版丢失wire但下行原clientRequestId可确定性恢复，保留最新草稿补PATCH', () async {
    remote.loseAck = true;
    final saved = await repo.save(oldDraft);
    await db.foodDao.upsertAll([
      saved.food
          .toCompanion(false)
          .copyWith(
            customCreateRequestSnapshot: const Value(null),
            customOriginLocalId: const Value(null),
          ),
    ]);
    await repo.update(saved.food, newDraft);
    await pullConfirmedIdentity(saved.food.customClientRequestId);
    expect(await repo.retryPending(), 1);
    expect(remote.cloud.length, 1);
    expect(remote.cloud.values.single.nameZh, newDraft.nameZh);
    final bound = (await db.foodDao.getById('server-1'))!;
    expect(bound.customOriginLocalId, saved.food.id);
    expect(bound.customSyncPending, isFalse);
  });
  for (final nextUser in ['review-user', 'other-user']) {
    test('create在途重新登录$nextUser使旧lease失效，不ACK原账号本地行', () async {
      final tokens = InMemoryTokenStore();
      await tokens.saveTokens(
        accessToken: 'token-1',
        refreshToken: 'refresh-1',
        userId: 'review-user',
      );
      final lease = SessionLease(tokens);
      remote.started = Completer<void>();
      remote.gate = Completer<void>();
      final started = remote.started!;
      final saving = lease.run(() => repo.save(oldDraft));
      final rejected = expectLater(
        saving,
        throwsA(isA<SessionChangedException>()),
      );
      await started.future;
      await tokens.saveTokens(
        accessToken: 'token-2',
        refreshToken: 'refresh-2',
        userId: nextUser,
      );
      remote.gate!.complete();
      await rejected;
      final rows = await db.foodDao.pendingCustomFoods(
        ownerUserId: 'review-user',
      );
      expect(rows, hasLength(1));
      expect(rows.single.customSyncPending, isTrue);
      expect(rows.single.id, startsWith('custom-'));
      expect(await db.foodDao.getById('server-1'), isNull);
      expect(
        await db.foodDao.pendingCustomFoods(ownerUserId: 'other-user'),
        isEmpty,
      );
    });
  }
}
