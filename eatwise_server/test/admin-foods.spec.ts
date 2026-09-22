import { randomUUID } from 'crypto';
import {
  CustomFoodEntity,
  DataStore,
  FoodEntity,
  FoodEntryEntity,
} from '../src/common/store/data-store';
import { BusinessException } from '../src/common/errors/business.exception';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

/**
 * 管理端食物库（GET/DELETE /admin/foods）核心逻辑：adminSearchFoods 跨用户可见
 * 自定义行（adminView）、adminDeleteFood 软删任意来源食物 + 跨用户级联 tombstone
 * 饮食记录、pending 候选 409、缺行/重删 404。内存驱动（与 prisma deletedAt 同语义）。
 */
describe('管理端食物库（FoodService.adminSearchFoods / adminDeleteFood）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;

  const USER_A = 'user_adminfood_a';
  const USER_B = 'user_adminfood_b';
  const SHARED_ID = 'shared_salad_001';
  const CUSTOM_A_ID = 'cf_adminfood_a1';
  const CUSTOM_B_ID = 'cf_adminfood_b1';

  const makeEntry = (userId: string, foodId: string): FoodEntryEntity => {
    const now = new Date();
    return {
      id: `fe_${randomUUID().slice(0, 8)}`,
      userId,
      clientRequestId: randomUUID(),
      eatenAt: now,
      foodId,
      grams: 100,
      inputMethod: 'manual',
      photoUrl: null,
      nutritionSnapshot: { kcal: 50, proteinG: 2, carbsG: 5, fatG: 2 },
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
  };

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

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
    const shared: FoodEntity = {
      id: SHARED_ID,
      nameZh: '蔬菜沙拉',
      nameEn: 'Garden Salad',
      aliases: [],
      kcalPer100g: 50,
      proteinPer100g: 2,
      carbsPer100g: 5,
      fatPer100g: 2,
      category: '菜品',
      source: 'usda',
    };
    store.foods.set(SHARED_ID, shared);
    const mkCustom = (id: string, userId: string): CustomFoodEntity => ({
      id,
      userId,
      clientRequestId: randomUUID(),
      nameZh: '蔬菜沙拉',
      nameEn: 'Veggie Salad',
      aliases: [],
      kcalPer100g: 55,
      proteinPer100g: 2,
      carbsPer100g: 6,
      fatPer100g: 2,
      source: 'manual',
      createdAt: new Date('2026-09-01T00:00:00Z'),
    });
    store.customFoods.set(CUSTOM_A_ID, mkCustom(CUSTOM_A_ID, USER_A));
    store.customFoods.set(CUSTOM_B_ID, mkCustom(CUSTOM_B_ID, USER_B));
  });

  // ===== 搜索 =====

  it('adminSearchFoods 返回共享 + 全部用户自定义（用户视角 search 只能见自己的）', async () => {
    const admin = await food.adminSearchFoods('蔬菜沙拉');
    expect(admin.items.map((i) => i.id).sort()).toEqual(
      [SHARED_ID, CUSTOM_A_ID, CUSTOM_B_ID].sort(),
    );
    // 契约字段：id/kcal/source/isCustom/deleted
    const custom = admin.items.find((i) => i.id === CUSTOM_B_ID)!;
    expect(custom).toMatchObject({
      kcalPer100g: 55,
      source: 'manual',
      isCustom: true,
      deleted: false,
    });
    const shared = admin.items.find((i) => i.id === SHARED_ID)!;
    expect(shared).toMatchObject({ kcalPer100g: 50, source: 'usda', isCustom: false });
    // 同一关键词，普通用户视角看不到他人自定义
    const asA = await food.search('蔬菜沙拉', 20, undefined, USER_A);
    expect(asA.items.map((i) => i.id)).not.toContain(CUSTOM_B_ID);
  });

  it('adminSearchFoods 空 q → 空集；游标分页 hasMore/nextCursor 口径同 search', async () => {
    expect((await food.adminSearchFoods('')).items).toEqual([]);
    const p1 = await food.adminSearchFoods('蔬菜沙拉', 2);
    expect(p1.items).toHaveLength(2);
    expect(p1.pageInfo.hasMore).toBe(true);
    expect(p1.pageInfo.nextCursor).not.toBeNull();
    const p2 = await food.adminSearchFoods('蔬菜沙拉', 2, p1.pageInfo.nextCursor!);
    expect(p2.items.map((i) => i.id)).not.toContain(p1.items[0].id);
    expect(p2.pageInfo.hasMore).toBe(false);
  });

  // ===== 删除 =====

  it('adminDeleteFood 删共享食物：软删后读路径隐藏，跨用户级联 tombstone，返回条数', async () => {
    await driver.saveFoodEntry(makeEntry(USER_A, SHARED_ID));
    await driver.saveFoodEntry(makeEntry(USER_B, SHARED_ID));
    await driver.saveFoodEntry(makeEntry(USER_B, SHARED_ID));
    const res = await food.adminDeleteFood(SHARED_ID);
    expect(res).toEqual({ deleted: true, deletedEntries: 3 });
    expect(await driver.findFoodById(SHARED_ID)).toBeNull();
    expect((await food.adminSearchFoods('蔬菜沙拉')).items.map((i) => i.id)).not.toContain(
      SHARED_ID,
    );
    for (const e of store.foodEntries.values()) {
      expect(e.deletedAt).not.toBeNull();
      expect(e.version).toBe(2);
    }
  });

  it('adminDeleteFood 删他人自定义食物（管理端无 owner 限制）', async () => {
    const res = await food.adminDeleteFood(CUSTOM_B_ID);
    expect(res).toEqual({ deleted: true, deletedEntries: 0 });
    expect(await driver.findCustomFoodById(CUSTOM_B_ID)).toBeNull();
    // B 的个人库视角即时隐藏；A 的自定义不受影响
    expect((await driver.searchFoods('蔬菜沙拉', USER_B)).map((h) => h.food.id)).not.toContain(
      CUSTOM_B_ID,
    );
    expect(await driver.findCustomFoodById(CUSTOM_A_ID)).not.toBeNull();
  });

  it('adminDeleteFood pending 候选关联 → 409 FOOD_UNDER_REVIEW，食物未删', async () => {
    await food.contributeCustomFood(USER_A, CUSTOM_A_ID, { clientRequestId: randomUUID() });
    await expectBusiness(food.adminDeleteFood(CUSTOM_A_ID), 'FOOD_UNDER_REVIEW', 409);
    expect(await driver.findCustomFoodById(CUSTOM_A_ID)).not.toBeNull();
  });

  it('adminDeleteFood 缺行 / 重删 → 404', async () => {
    await expectBusiness(food.adminDeleteFood('missing_id'), 'NOT_FOUND', 404);
    await food.adminDeleteFood(CUSTOM_A_ID);
    await expectBusiness(food.adminDeleteFood(CUSTOM_A_ID), 'NOT_FOUND', 404);
  });

  it('已删食物的既有 tombstone 记录不重复计数（级联幂等）', async () => {
    await driver.saveFoodEntry(makeEntry(USER_A, CUSTOM_B_ID));
    expect((await food.adminDeleteFood(CUSTOM_B_ID)).deletedEntries).toBe(1);
    await expectBusiness(food.adminDeleteFood(CUSTOM_B_ID), 'NOT_FOUND', 404);
    // 再调 driver 原语仍 0（已删行不再变动）
    expect(await driver.softDeleteAllFoodEntriesByFood(CUSTOM_B_ID)).toBe(0);
  });
});
