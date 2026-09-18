import { randomUUID } from 'crypto';
import { DataStore, FoodEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

/**
 * 食物数据纠错（食物详情页「数据有误？」入口，kind=correction）：
 * 提交校验（目标须共享库食物/营养区间/同人同食物 pending 去重）、
 * 审核 approve 应用建议值到共享食物行 / reject 退回。
 */
describe('食物数据纠错（FoodService.createFoodCorrection）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;

  const USER = 'user_correction_1';
  const FOOD_ID = 'f_builtin_rice';

  interface CandidateView {
    id: string;
    foodId: string;
    status: string;
    kind: string;
    suggestion: {
      nameZh: string | null;
      nameEn: string | null;
      per100g: { kcal: number; proteinG: number; carbG: number; fatG: number };
    } | null;
    per100g: { kcal: number; proteinG: number; carbG: number; fatG: number } | null;
  }

  const submit = async (
    extra: {
      nameZh?: string;
      nameEn?: string;
      per100g?: { kcal: number; proteinG: number; carbG: number; fatG: number };
    } = {},
    userId = USER,
  ): Promise<CandidateView> =>
    (await food.createFoodCorrection(userId, FOOD_ID, {
      clientRequestId: randomUUID(),
      per100g: { kcal: 130, proteinG: 2.7, carbG: 28, fatG: 0.3 },
      ...extra,
    })) as CandidateView;

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
    const builtin: FoodEntity = {
      id: FOOD_ID,
      nameZh: '白米饭',
      nameEn: 'White Rice',
      aliases: ['米饭'],
      kcalPer100g: 116,
      proteinPer100g: 2.6,
      carbsPer100g: 25.9,
      fatPer100g: 0.3,
      category: '主食',
      source: 'cn_fct',
    };
    store.foods.set(FOOD_ID, builtin);
  });

  it('提交成功：kind=correction，建议值入候选视图，原值（per100g）为当前库值', async () => {
    const res = await submit({ nameZh: '白米饭（熟）' });
    expect(res).toMatchObject({
      foodId: FOOD_ID,
      status: 'pending',
      kind: 'correction',
      suggestion: {
        nameZh: '白米饭（熟）',
        nameEn: null,
        per100g: { kcal: 130, proteinG: 2.7, carbG: 28, fatG: 0.3 },
      },
      per100g: { kcal: 116, proteinG: 2.6, carbG: 25.9, fatG: 0.3 },
    });
  });

  it('名称与库值相同 → 建议名归一为 null（审核台只看真正的改动）', async () => {
    const res = await submit({ nameZh: '白米饭', nameEn: 'White Rice' });
    expect(res.suggestion?.nameZh).toBeNull();
    expect(res.suggestion?.nameEn).toBeNull();
  });

  it('目标食物不在共享库 → 404 NOT_FOUND（自定义食物同样拒）', async () => {
    await expect(
      food.createFoodCorrection(USER, 'cf_missing', {
        clientRequestId: randomUUID(),
        per100g: { kcal: 100, proteinG: 1, carbG: 1, fatG: 1 },
      }),
    ).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });

  it('营养越界（kcal >900 / 宏量 >100）→ 400 VALIDATION_ERROR', async () => {
    for (const bad of [
      { kcal: 901, proteinG: 1, carbG: 1, fatG: 1 },
      { kcal: 100, proteinG: 101, carbG: 1, fatG: 1 },
    ]) {
      await expect(submit({ per100g: bad })).rejects.toMatchObject({
        code: 'VALIDATION_ERROR',
      });
    }
  });

  it('同人同食物已有 pending 纠错 → 幂等返回原候选（不堆队列、建议值不覆盖）', async () => {
    const first = await submit({ nameZh: '第一次建议' });
    const second = await submit({ nameZh: '第二次建议' });
    expect(second.id).toBe(first.id);
    expect(second.suggestion?.nameZh).toBe('第一次建议');
    const queue = await food.listFoodCandidates('pending', 20, undefined);
    expect(queue.items).toHaveLength(1);
  });

  it('clientRequestId 重放返回首次结果；同键不同体 → 409 PAYLOAD_MISMATCH', async () => {
    const clientRequestId = randomUUID();
    const dto = {
      clientRequestId,
      per100g: { kcal: 130, proteinG: 2.7, carbG: 28, fatG: 0.3 },
    };
    const first = (await food.createFoodCorrection(USER, FOOD_ID, dto)) as CandidateView;
    const replay = (await food.createFoodCorrection(USER, FOOD_ID, dto)) as CandidateView;
    expect(replay.id).toBe(first.id);
    await expect(
      food.createFoodCorrection(USER, FOOD_ID, {
        clientRequestId,
        per100g: { kcal: 131, proteinG: 2.7, carbG: 28, fatG: 0.3 },
      }),
    ).rejects.toMatchObject({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' });
  });

  it('approve：建议值应用到共享食物行（改名 + 四营养覆写），候选转 approved', async () => {
    const res = await submit({ nameZh: '白米饭（熟）', nameEn: 'Cooked White Rice' });
    const reviewed = (await food.reviewFoodCandidate(res.id, {
      action: 'approve',
    })) as CandidateView;
    expect(reviewed.status).toBe('approved');
    const updated = await driver.findFoodById(FOOD_ID);
    expect(updated).toMatchObject({
      nameZh: '白米饭（熟）',
      nameEn: 'Cooked White Rice',
      kcalPer100g: 130,
      proteinPer100g: 2.7,
      carbsPer100g: 28,
      fatPer100g: 0.3,
    });
  });

  it('approve：建议名为 null 时只覆写营养，名称保持原值', async () => {
    const res = await submit();
    await food.reviewFoodCandidate(res.id, { action: 'approve' });
    const updated = await driver.findFoodById(FOOD_ID);
    expect(updated?.nameZh).toBe('白米饭');
    expect(updated?.kcalPer100g).toBe(130);
  });

  it('reject：状态 rejected + reason，共享食物行不变；之后可重新提交纠错', async () => {
    const res = await submit();
    const reviewed = (await food.reviewFoodCandidate(res.id, {
      action: 'reject',
      reason: '数值与来源不符',
    })) as CandidateView & { reason: string | null };
    expect(reviewed.status).toBe('rejected');
    expect(reviewed.reason).toBe('数值与来源不符');
    const unchanged = await driver.findFoodById(FOOD_ID);
    expect(unchanged?.kcalPer100g).toBe(116);
    // rejected 不阻断重提交（pending 去重只挡 pending）。
    const again = await submit();
    expect(again.id).not.toBe(res.id);
    expect(again.status).toBe('pending');
  });

  it('我的贡献列表包含纠错条目（kind=correction）', async () => {
    await submit();
    const mine = await food.findContributionsByUser(USER, undefined, 1, 20);
    expect(mine.total).toBe(1);
    expect(mine.items[0]).toMatchObject({ foodId: FOOD_ID, kind: 'correction', status: 'pending' });
  });
});
