import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { SyncService } from '../src/sync/sync.service';

/**
 * 乐观入账与审核联动（「没有计入库的食品可以先记录，审批不通过再清除」）：
 * - 根因修复：自定义食物（个人库）的记录上行不再 4xx（snapshotOf 回落本人自定义食物）；
 * - reject → 级联软删贡献者引用该食物的记录（sync/pull 下行 tombstone）且幂等；
 * - approve → 条目保留（营养快照不回溯）；kind=correction 驳回不动记录。
 */
describe('乐观入账与审核联动（候选驳回级联清除记录）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;
  let sync: SyncService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
    sync = new SyncService(driver, new NutritionService(driver));
    userId = store.createUser({ phone: '+8613800138000' }).id;
  });

  const createCustom = (nameZh = '乐观入账臊子面', uid = userId) =>
    food.createCustomFood(uid, {
      clientRequestId: randomUUID(),
      nameZh,
      per100g: { kcal: 200, proteinG: 8, carbG: 30, fatG: 5 },
      source: 'manual',
    });

  const pushEntry = (foodId: string, grams = 150, uid = userId) =>
    sync.push(uid, [
      {
        clientRequestId: randomUUID(),
        entity: 'foodEntry',
        op: 'create',
        payload: {
          eatenAt: '2026-09-19T04:10:00.000Z',
          foodId,
          grams,
          inputMethod: 'manual',
        },
      },
    ]);

  const activeEntries = (uid = userId) =>
    [...store.foodEntries.values()].filter((e) => e.userId === uid && !e.deletedAt);

  it('乐观入账：引用本人自定义食物的记录上行 applied（不再 4xx 静默丢失），快照按自定义食物换算', async () => {
    const custom = (await createCustom()) as { id: string };
    const res = await pushEntry(custom.id, 150);
    expect(res.results[0].status).toBe('applied');
    const entry = res.results[0].serverEntry as {
      foodId: string;
      nutritionSnapshot: { kcal: number; proteinG: number };
    };
    expect(entry.foodId).toBe(custom.id);
    expect(entry.nutritionSnapshot.kcal).toBe(300); // 200 × 1.5
    expect(entry.nutritionSnapshot.proteinG).toBe(12);
  });

  it('他人自定义食物不可入账（可见性防腐）：error VALIDATION_ERROR', async () => {
    const strangerId = store.createUser({ phone: '+8613800138001' }).id;
    const custom = (await createCustom('他人私房菜', strangerId)) as { id: string };
    const res = await pushEntry(custom.id);
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');
    expect(activeEntries()).toHaveLength(0);
  });

  it('未知 foodId 仍 VALIDATION_ERROR（口径不变）', async () => {
    const res = await pushEntry('f_not_exist');
    expect(res.results[0].status).toBe('error');
    expect(res.results[0].error?.code).toBe('VALIDATION_ERROR');
  });

  it('reject → 贡献者引用该食物的记录级联软删，sync/pull 下行 tombstone', async () => {
    const custom = (await createCustom()) as { id: string };
    await pushEntry(custom.id);
    await pushEntry(custom.id);
    expect(activeEntries()).toHaveLength(2);

    const candidate = (await food.contributeCustomFood(userId, custom.id, {
      clientRequestId: randomUUID(),
    })) as { id: string };
    await food.reviewFoodCandidate(candidate.id, { action: 'reject', reason: '营养数据存疑' });

    expect(activeEntries()).toHaveLength(0);
    const pull = await sync.pull(userId, undefined);
    const tombstones = pull.changes.filter((c) => 'tombstone' in c);
    expect(tombstones).toHaveLength(2);
  });

  it('reject 幂等：重复驳回返回 rejected 视图不报错，reason 不覆写，记录不重复处理', async () => {
    const custom = (await createCustom()) as { id: string };
    await pushEntry(custom.id);
    const candidate = (await food.contributeCustomFood(userId, custom.id, {
      clientRequestId: randomUUID(),
    })) as { id: string };

    await food.reviewFoodCandidate(candidate.id, { action: 'reject', reason: '首次原因' });
    const again = (await food.reviewFoodCandidate(candidate.id, {
      action: 'reject',
      reason: '二次原因',
    })) as { status: string; reason: string };
    expect(again.status).toBe('rejected');
    expect(again.reason).toBe('首次原因');
    expect(activeEntries()).toHaveLength(0);
    expect([...store.foodEntries.values()]).toHaveLength(1); // 未多出记录也未重复变更
  });

  it('approve 后条目保留（快照不回溯），重复 approve 仍 409（现有行为不变）', async () => {
    const custom = (await createCustom('晋升油泼面')) as { id: string };
    await pushEntry(custom.id, 100);
    const candidate = (await food.contributeCustomFood(userId, custom.id, {
      clientRequestId: randomUUID(),
    })) as { id: string };

    await food.reviewFoodCandidate(candidate.id, { action: 'approve' });
    expect(activeEntries()).toHaveLength(1);
    const kept = activeEntries()[0];
    expect(kept.nutritionSnapshot.kcal).toBe(200); // 快照口径：晋升后不回溯重算

    await expect(
      food.reviewFoodCandidate(candidate.id, { action: 'approve' }),
    ).rejects.toThrow(expect.objectContaining({ code: 'CONFLICT' }) as unknown as Error);
    await expect(
      food.reviewFoodCandidate(candidate.id, { action: 'reject', reason: '事后驳回' }),
    ).rejects.toThrow(expect.objectContaining({ code: 'CONFLICT' }) as unknown as Error);
    expect(activeEntries()).toHaveLength(1); // 驳回已共享候选不动记录
  });

  it('kind=correction 驳回不动记录（目标食物仍在共享库）', async () => {
    const builtin = [...store.foods.values()][0];
    await pushEntry(builtin.id);
    const candidate = (await food.createFoodCorrection(userId, builtin.id, {
      clientRequestId: randomUUID(),
      per100g: { kcal: 130, proteinG: 2.7, carbG: 28, fatG: 0.3 },
    })) as { id: string };

    await food.reviewFoodCandidate(candidate.id, { action: 'reject', reason: '原值无误' });
    expect(activeEntries()).toHaveLength(1);
  });
});
