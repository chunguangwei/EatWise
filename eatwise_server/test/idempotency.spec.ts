import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { SyncService } from '../src/sync/sync.service';
import { CreateEntryDto } from '../src/sync/sync.dto';

/** 幂等重放（D-20）：同 clientRequestId 不重复入账 */
describe('幂等：clientRequestId 去重', () => {
  let store: DataStore;
  let sync: SyncService;
  let userId: string;
  let foodId: string;

  beforeEach(() => {
    store = new DataStore();
    sync = new SyncService(store, new NutritionService(store));
    userId = store.createUser({ phone: '+8613800138000' }).id;
    foodId = [...store.foods.values()][0].id;
  });

  const dto = (): CreateEntryDto => ({
    clientRequestId: randomUUID(),
    eatenAt: '2026-07-27T04:10:00.000Z',
    foodId,
    grams: 200,
    inputMethod: 'manual',
  });

  it('同一 clientRequestId 重放返回首次结果，不重复落库', () => {
    const req = dto();
    const first = sync.createEntry(userId, req) as { entry: { id: string } };
    const second = sync.createEntry(userId, req) as { entry: { id: string } };
    const third = sync.createEntry(userId, req) as { entry: { id: string } };

    expect(second.entry.id).toBe(first.entry.id);
    expect(third.entry.id).toBe(first.entry.id);
    const count = [...store.foodEntries.values()].filter((e) => e.userId === userId).length;
    expect(count).toBe(1);
  });

  it('同 clientRequestId 但请求体不同 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', () => {
    const req = dto();
    sync.createEntry(userId, req);
    expect(() => sync.createEntry(userId, { ...req, grams: 300 })).toThrow(
      expect.objectContaining({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' }) as unknown as Error,
    );
  });

  it('批量上行内 create 重放：status=applied 且不产生新记录', () => {
    const clientRequestId = randomUUID();
    const op = {
      clientRequestId,
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 200, inputMethod: 'manual' },
    };
    const r1 = sync.push(userId, [op]).results[0];
    const r2 = sync.push(userId, [op]).results[0];
    expect(r1.status).toBe('applied');
    expect(r2.status).toBe('applied');
    expect((r2.serverEntry as { id: string }).id).toBe((r1.serverEntry as { id: string }).id);
    expect([...store.foodEntries.values()].length).toBe(1);
  });

  it('批量上行 create 同键不同体 → 该条 error IDEMPOTENCY_PAYLOAD_MISMATCH，不中断整批', () => {
    const clientRequestId = randomUUID();
    const base = {
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 200 },
    };
    sync.push(userId, [{ ...base, clientRequestId }]);
    const res = sync.push(userId, [
      { ...base, clientRequestId, payload: { ...base.payload, grams: 999 } },
      { ...base, clientRequestId: randomUUID() },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    expect(res.results[1].status).toBe('applied');
  });
});
