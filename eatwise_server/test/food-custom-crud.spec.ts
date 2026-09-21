import { randomUUID } from 'crypto';
import { CustomFoodEntity, DataStore, FoodEntryEntity } from '../src/common/store/data-store';
import { BusinessException } from '../src/common/errors/business.exception';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

/**
 * 自定义食物改/删（PATCH/DELETE /foods/custom/:id）：owner 校验、校验口径同创建、
 * 审核中（pending 候选）删除 409、rejected 候选可删、软删后读路径隐藏、
 * 级联 tombstone 饮食记录、重删 404。内存驱动（与 prisma deletedAt 过滤同语义）。
 */
describe('自定义食物改/删（FoodService.updateCustomFood / deleteCustomFood）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;

  const OWNER = 'user_custom_crud_1';
  const OTHER = 'user_custom_crud_2';
  const FOOD_ID = 'cf_mine_001';

  interface CustomView {
    id: string;
    nameZh: string;
    nameEn: string;
    aliases: string[];
    per100g: { kcal: number; proteinG: number; carbG: number; fatG: number };
    source: string;
    isCustom: boolean;
  }

  const patchDto = (
    extra: Partial<{
      nameZh: string;
      nameEn: string;
      aliasesZh: string[];
      per100g: { kcal: number; proteinG: number; carbG: number; fatG: number };
    }> = {},
  ) => ({
    nameZh: '自制鸡胸肉',
    per100g: { kcal: 165, proteinG: 31, carbG: 0, fatG: 3.6 },
    source: 'manual' as const,
    ...extra,
  });

  const expectBusiness = async (p: Promise<unknown>, code: string, status: number) => {
    await expect(p).rejects.toBeInstanceOf(BusinessException);
    try {
      await p;
      throw new Error('expected BusinessException');
    } catch (e) {
      const be = e as BusinessException;
      expect(be.code).toBe(code);
      expect(be.getStatus()).toBe(status);
    }
  };

  const makeEntry = (clientRequestId: string): FoodEntryEntity => {
    const now = new Date();
    return {
      id: `fe_${clientRequestId.slice(0, 8)}`,
      userId: OWNER,
      clientRequestId,
      eatenAt: now,
      foodId: FOOD_ID,
      grams: 100,
      inputMethod: 'manual',
      photoUrl: null,
      nutritionSnapshot: { kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6 },
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
  };

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
    const custom: CustomFoodEntity = {
      id: FOOD_ID,
      userId: OWNER,
      clientRequestId: randomUUID(),
      nameZh: '自制酸奶',
      nameEn: 'Homemade Yogurt',
      aliases: ['酸奶碗'],
      kcalPer100g: 60,
      proteinPer100g: 3.5,
      carbsPer100g: 7,
      fatPer100g: 2.5,
      source: 'manual',
      createdAt: new Date('2026-09-01T00:00:00Z'),
    };
    store.customFoods.set(FOOD_ID, custom);
  });

  // ===== PATCH =====

  it('PATCH owner 改值成功：视图返回新值，读回（search/get）即新值', async () => {
    const res = (await food.updateCustomFood(OWNER, FOOD_ID, patchDto({
      nameZh: ' 自制鸡胸肉 ',
      nameEn: 'Chicken Breast',
      aliasesZh: [' 鸡胸 ', ''],
      per100g: { kcal: 165, proteinG: 31, carbG: 0, fatG: 3.6 },
    }))) as CustomView;
    expect(res).toMatchObject({
      id: FOOD_ID,
      nameZh: '自制鸡胸肉',
      nameEn: 'Chicken Breast',
      aliases: ['鸡胸'],
      per100g: { kcal: 165, proteinG: 31, carbG: 0, fatG: 3.6 },
      source: 'manual',
      isCustom: true,
    });
    const stored = await driver.findCustomFoodById(FOOD_ID);
    expect(stored?.nameZh).toBe('自制鸡胸肉');
    const hits = await driver.searchFoods('鸡胸', OWNER);
    expect(hits.map((h) => h.food.id)).toContain(FOOD_ID);
  });

  it('PATCH 未给英文名 → 回退中文名（同 create 口径）', async () => {
    const res = (await food.updateCustomFood(OWNER, FOOD_ID, patchDto())) as CustomView;
    expect(res.nameEn).toBe('自制鸡胸肉');
  });

  it('PATCH 非 owner / 不存在 → 404（不泄露存在性）', async () => {
    await expectBusiness(
      food.updateCustomFood(OTHER, FOOD_ID, patchDto()),
      'NOT_FOUND',
      404,
    );
    await expectBusiness(
      food.updateCustomFood(OWNER, 'cf_missing', patchDto()),
      'NOT_FOUND',
      404,
    );
    // 非 owner 改不动
    expect((await driver.findCustomFoodById(FOOD_ID))?.nameZh).toBe('自制酸奶');
  });

  it('PATCH 营养越界 / 名称 trim 后超 50 字 → 400 VALIDATION_ERROR', async () => {
    await expectBusiness(
      food.updateCustomFood(OWNER, FOOD_ID, patchDto({ per100g: { kcal: 1000, proteinG: 0, carbG: 0, fatG: 0 } })),
      'VALIDATION_ERROR',
      400,
    );
    await expectBusiness(
      food.updateCustomFood(OWNER, FOOD_ID, patchDto({ nameZh: '自'.padEnd(52, '字') })),
      'VALIDATION_ERROR',
      400,
    );
    expect((await driver.findCustomFoodById(FOOD_ID))?.kcalPer100g).toBe(60);
  });

  // ===== DELETE =====

  it('DELETE pending 候选（审核中）→ 409 FOOD_UNDER_REVIEW，食物未删', async () => {
    await food.contributeCustomFood(OWNER, FOOD_ID, { clientRequestId: randomUUID() });
    await expectBusiness(
      food.deleteCustomFood(OWNER, FOOD_ID),
      'FOOD_UNDER_REVIEW',
      409,
    );
    expect(await driver.findCustomFoodById(FOOD_ID)).not.toBeNull();
  });

  it('DELETE rejected 候选可删（审核台视图回退 null 不悬空）', async () => {
    const contributed = (await food.contributeCustomFood(OWNER, FOOD_ID, {
      clientRequestId: randomUUID(),
    })) as { id: string };
    await food.reviewFoodCandidate(contributed.id, { action: 'reject', reason: '信息不全' });
    const res = await food.deleteCustomFood(OWNER, FOOD_ID);
    expect(res).toEqual({ deleted: true, deletedEntries: 0 });
    expect(await driver.findCustomFoodById(FOOD_ID)).toBeNull();
  });

  it('DELETE 非 owner / 共享食物 → 404；删除后 search/get 不再命中', async () => {
    await expectBusiness(food.deleteCustomFood(OTHER, FOOD_ID), 'NOT_FOUND', 404);
    expect(await driver.searchFoods('酸奶', OTHER)).toEqual([]);

    const hitsBefore = await driver.searchFoods('酸奶', OWNER);
    expect(hitsBefore.map((h) => h.food.id)).toContain(FOOD_ID);

    await food.deleteCustomFood(OWNER, FOOD_ID);
    expect(await driver.searchFoods('酸奶', OWNER)).toEqual([]);
    expect(await driver.findCustomFoodById(FOOD_ID)).toBeNull();
    expect(await food.getById(FOOD_ID, OWNER)).toBeUndefined();
    expect(await driver.findCustomFoodsByUser(OWNER)).toEqual([]);
  });

  it('DELETE 级联：本人引用该食物的饮食记录全部 tombstone（version+1），返回条数', async () => {
    await driver.saveFoodEntry(makeEntry(randomUUID()));
    await driver.saveFoodEntry(makeEntry(randomUUID()));
    const res = await food.deleteCustomFood(OWNER, FOOD_ID);
    expect(res.deleted).toBe(true);
    expect(res.deletedEntries).toBe(2);
    const entries = [...store.foodEntries.values()];
    expect(entries).toHaveLength(2);
    for (const e of entries) {
      expect(e.deletedAt).not.toBeNull();
      expect(e.version).toBe(2);
    }
  });

  it('DELETE 二次删除 → 404（资源已不存在的自然语义，不做幂等重放）', async () => {
    await food.deleteCustomFood(OWNER, FOOD_ID);
    await expectBusiness(food.deleteCustomFood(OWNER, FOOD_ID), 'NOT_FOUND', 404);
  });
});
