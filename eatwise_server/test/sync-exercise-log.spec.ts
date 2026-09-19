import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { SyncService } from '../src/sync/sync.service';

/** exerciseLog 轻量两态同步（手动记运动/截图导入上行，2026-09-19 拍板）：
 * create/delete 幂等 + 随 /sync/pull 下行；口径与 waterLog 一致 */
describe('sync：exerciseLog op（轻量两态，无 update）', () => {
  let store: DataStore;
  let sync: SyncService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    const driver = new MemoryStoreDriver(store);
    sync = new SyncService(driver, new NutritionService(driver));
    userId = store.createUser({ phone: '+8613800138000' }).id;
  });

  function createExerciseOp(clientRequestId = randomUUID()) {
    return {
      clientRequestId,
      entity: 'exerciseLog',
      op: 'create',
      payload: {
        typeKey: 'walk',
        durationMin: 0,
        kcal: 68,
        steps: 1466,
        source: 'screenshot',
        loggedAt: '2026-09-19T02:00:00.000Z',
        localDate: '2026-09-19',
      },
    };
  }

  it('create applied：落库并返回服务端视图（含 serverId/类型/步数/来源）', async () => {
    const res = await sync.push(userId, [createExerciseOp()]);
    const r = res.results[0];
    expect(r.status).toBe('applied');
    const view = r.serverEntry as {
      id: string;
      typeKey: string;
      durationMin: number;
      kcal: number;
      steps: number | null;
      source: string | null;
      version: number;
    };
    expect(view.id).toBeTruthy();
    expect(view.typeKey).toBe('walk');
    expect(view.durationMin).toBe(0);
    expect(view.kcal).toBe(68);
    expect(view.steps).toBe(1466);
    expect(view.source).toBe('screenshot');
    expect(view.version).toBe(1);
    expect(store.exerciseLogs.size).toBe(1);
  });

  it('create：steps/source 可空（纯手动录入无时长短跑也能落）', async () => {
    const op = createExerciseOp();
    const res = await sync.push(userId, [
      {
        ...op,
        payload: {
          typeKey: 'jog',
          durationMin: 30,
          kcal: 210,
          loggedAt: '2026-09-19T03:00:00.000Z',
          localDate: '2026-09-19',
        },
      },
    ]);
    expect(res.results[0].status).toBe('applied');
    const view = res.results[0].serverEntry as { steps: number | null; source: string | null };
    expect(view.steps).toBeNull();
    expect(view.source).toBeNull();
  });

  it('create 幂等：同 clientRequestId 重放返回首次结果，不重复落库', async () => {
    const op = createExerciseOp();
    const first = (await sync.push(userId, [op])).results[0];
    const second = (await sync.push(userId, [op])).results[0];
    expect(second.status).toBe('applied');
    expect((second.serverEntry as { id: string }).id).toBe(
      (first.serverEntry as { id: string }).id,
    );
    expect(store.exerciseLogs.size).toBe(1);
  });

  it('create 同键不同体 → IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const op = createExerciseOp();
    await sync.push(userId, [op]);
    const res = await sync.push(userId, [{ ...op, payload: { ...op.payload, kcal: 100 } }]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    expect(store.exerciseLogs.size).toBe(1);
  });

  it('create 缺 typeKey/kcal/loggedAt 或 kcal≤0 → VALIDATION_ERROR', async () => {
    const res = await sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'exerciseLog', op: 'create', payload: {} },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');

    const bad = createExerciseOp();
    const res2 = await sync.push(userId, [{ ...bad, payload: { ...bad.payload, kcal: 0 } }]);
    expect(res2.results[0].status).toBe('error');
    expect(res2.results[0].error?.code).toBe('VALIDATION_ERROR');
  });

  it('delete：按 serverId 软删；重复删除幂等返回 applied', async () => {
    const created = (await sync.push(userId, [createExerciseOp()])).results[0];
    const serverId = (created.serverEntry as { id: string }).id;
    const del = {
      clientRequestId: randomUUID(),
      entity: 'exerciseLog',
      op: 'delete',
      serverId,
    };
    expect((await sync.push(userId, [del])).results[0].status).toBe('applied');
    expect(store.exerciseLogs.get(serverId)!.deletedAt).not.toBeNull();
    expect(
      (await sync.push(userId, [{ ...del, clientRequestId: randomUUID() }])).results[0].status,
    ).toBe('applied');
  });

  it('delete：serverId 丢失时按 payload.clientRequestId 兜底定位（响应丢失场景）', async () => {
    const rowKey = randomUUID();
    await sync.push(userId, [createExerciseOp(rowKey)]);
    const res = await sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'exerciseLog',
        op: 'delete',
        payload: { clientRequestId: rowKey },
      },
    ]);
    expect(res.results[0].status).toBe('applied');
    expect([...store.exerciseLogs.values()][0].deletedAt).not.toBeNull();
  });

  it('delete 未知记录 → NOT_FOUND（客户端据此丢弃本地 tombstone）', async () => {
    const res = await sync.push(userId, [
      {
        clientRequestId: randomUUID(),
        entity: 'exerciseLog',
        op: 'delete',
        serverId: 'e-ghost',
      },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('NOT_FOUND');
  });

  it('update op 不支持 → VALIDATION_ERROR（两态无编辑场景）', async () => {
    const res = await sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'exerciseLog', op: 'update', payload: {} },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');
  });

  it('/sync/pull：exerciseLogChanges 含新建与 tombstone，且与 foodEntry/waterLog 互不影响', async () => {
    const created = (await sync.push(userId, [createExerciseOp()])).results[0];
    const serverId = (created.serverEntry as { id: string }).id;

    const pull1 = await sync.pull(userId, undefined);
    expect(pull1.exerciseLogChanges.length).toBe(1);
    expect((pull1.exerciseLogChanges[0] as { steps: number }).steps).toBe(1466);
    expect(pull1.changes.length).toBe(0); // 无 foodEntry
    expect(pull1.waterLogChanges.length).toBe(0); // 无 waterLog

    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    await sync.push(userId, [
      { clientRequestId: randomUUID(), entity: 'exerciseLog', op: 'delete', serverId },
    ]);

    const pull2 = await sync.pull(userId, pull1.syncToken);
    expect(pull2.exerciseLogChanges.length).toBe(1);
    const tomb = pull2.exerciseLogChanges[0] as { tombstone: { id: string; entity: string } };
    expect(tomb.tombstone.id).toBe(serverId);
    expect(tomb.tombstone.entity).toBe('exerciseLog');
  });

  it('跨端场景：B 机全量 pull 能拿到 A 机上行的记录', async () => {
    await sync.push(userId, [createExerciseOp()]);
    // B 机首次同步（无 syncToken）→ 全量下行
    const pull = await sync.pull(userId, undefined);
    expect(pull.exerciseLogChanges.length).toBe(1);
    const view = pull.exerciseLogChanges[0] as {
      typeKey: string;
      steps: number;
      kcal: number;
      localDate: string;
    };
    expect(view.typeKey).toBe('walk');
    expect(view.steps).toBe(1466);
    expect(view.kcal).toBe(68);
    expect(view.localDate).toBe('2026-09-19');
  });

  it('他用户数据隔离：pull 不返回他人 exerciseLog', async () => {
    const otherId = store.createUser({ phone: '+8613900139000' }).id;
    await sync.push(otherId, [createExerciseOp()]);
    const pull = await sync.pull(userId, undefined);
    expect(pull.exerciseLogChanges.length).toBe(0);
  });
});
