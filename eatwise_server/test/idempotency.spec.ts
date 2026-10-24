import { randomUUID } from 'crypto';
import { ConfigService } from '@nestjs/config';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StreakService } from '../src/streak/streak.service';
import { SyncService } from '../src/sync/sync.service';
import { CreateEntryDto } from '../src/sync/sync.dto';

/** 幂等重放（D-20）：同 clientRequestId 不重复入账 */
describe('幂等：clientRequestId 去重', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let streak: StreakService;
  let sync: SyncService;
  let userId: string;
  let foodId: string;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    streak = new StreakService(driver);
    sync = new SyncService(driver, new NutritionService(driver), streak, new ConfigService());
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

  it('同一 clientRequestId 重放返回首次结果，不重复落库', async () => {
    const req = dto();
    const first = (await sync.createEntry(userId, req)) as { entry: { id: string } };
    const second = (await sync.createEntry(userId, req)) as { entry: { id: string } };
    const third = (await sync.createEntry(userId, req)) as { entry: { id: string } };

    expect(second.entry.id).toBe(first.entry.id);
    expect(third.entry.id).toBe(first.entry.id);
    const count = [...store.foodEntries.values()].filter((e) => e.userId === userId).length;
    expect(count).toBe(1);
  });

  it('同 clientRequestId 但请求体不同 → 409 IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const req = dto();
    await sync.createEntry(userId, req);
    await expect(sync.createEntry(userId, { ...req, grams: 300 })).rejects.toThrow(
      expect.objectContaining({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' }) as unknown as Error,
    );
  });

  it('批量上行内 create 重放：status=applied 且不产生新记录', async () => {
    const clientRequestId = randomUUID();
    const op = {
      clientRequestId,
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 200, inputMethod: 'manual' },
    };
    const r1 = (await sync.push(userId, [op])).results[0];
    const r2 = (await sync.push(userId, [op])).results[0];
    expect(r1.status).toBe('applied');
    expect(r2.status).toBe('applied');
    expect((r2.serverEntry as { id: string }).id).toBe((r1.serverEntry as { id: string }).id);
    expect([...store.foodEntries.values()].length).toBe(1);
  });

  it('批量上行 create 同键不同体 → 该条 error IDEMPOTENCY_PAYLOAD_MISMATCH，不中断整批', async () => {
    const clientRequestId = randomUUID();
    const base = {
      entity: 'foodEntry',
      op: 'create',
      payload: { eatenAt: '2026-07-27T04:10:00.000Z', foodId, grams: 200 },
    };
    await sync.push(userId, [{ ...base, clientRequestId }]);
    const res = await sync.push(userId, [
      { ...base, clientRequestId, payload: { ...base.payload, grams: 999 } },
      { ...base, clientRequestId: randomUUID() },
    ]);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');
    expect(res.results[1].status).toBe('applied');
  });

  it('E1 业务行已落但回执缺失：同体重建 entry + dailyNutrition 并补回执', async () => {
    const req = dto();
    const first = await sync.createEntry(userId, req);
    store.idempotency.clear();

    const recovered = await sync.createEntry(userId, req);
    expect(recovered).toEqual(first);
    expect(store.idempotency.size).toBe(1);
    expect([...store.foodEntries.values()]).toHaveLength(1);
    expect(
      (recovered as { entry: { id: string }; dailyNutrition: { kcal: number } }).dailyNutrition
        .kcal,
    ).toBeGreaterThan(0);
  });

  it('E1 回执缺失但同键异体：409，不覆盖业务行也不补回执', async () => {
    const req = dto();
    const first = (await sync.createEntry(userId, req)) as { entry: { id: string } };
    store.idempotency.clear();

    await expect(sync.createEntry(userId, { ...req, grams: req.grams + 1 })).rejects.toThrow(
      expect.objectContaining({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' }) as unknown as Error,
    );
    expect([...store.foodEntries.values()]).toHaveLength(1);
    expect(store.foodEntries.get(first.entry.id)?.grams).toBe(req.grams);
    expect(store.idempotency.size).toBe(0);
  });

  it('push/pull 即使无断食变更也触发滞后月份 rollover', async () => {
    const initial = await streak.getOrCreate(userId);
    const currentMonth = initial.makeupCards.month;
    initial.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await driver.saveStreak(initial);
    await sync.pull(userId, undefined);
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: currentMonth,
      usedDates: [],
    });

    const stale = await driver.findStreakByUser(userId);
    stale!.makeupCards = { stock: 0, month: '2000-01', usedDates: ['2000-01-02'] };
    await driver.saveStreak(stale!);
    await sync.push(userId, []);
    expect((await driver.findStreakByUser(userId))?.makeupCards).toEqual({
      stock: 2,
      month: currentMonth,
      usedDates: [],
    });
  });
});
