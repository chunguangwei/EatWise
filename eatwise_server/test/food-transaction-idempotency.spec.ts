import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

describe('FoodService 事务幂等', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;
  let userId: string;

  const createDto = (clientRequestId = randomUUID()) => ({
    clientRequestId,
    nameZh: '事务酸奶',
    nameEn: 'Transactional Yogurt',
    aliasesZh: ['酸奶'],
    per100g: { kcal: 60, proteinG: 3.5, carbG: 7, fatG: 2.5 },
    source: 'manual' as const,
  });

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
    userId = store.createUser({ phone: '+8613800138000' }).id;
  });

  it('createCustomFood 同键并发只落一条业务行和一张回执', async () => {
    const dto = createDto();
    const [first, replay] = await Promise.all([
      food.createCustomFood(userId, dto),
      food.createCustomFood(userId, dto),
    ]);
    expect(replay).toEqual(first);
    expect(store.customFoods.size).toBe(1);
    expect(store.idempotency.size).toBe(1);
  });

  it('createCustomFood 回执缺失可按请求键恢复残留；异体 409', async () => {
    const dto = createDto();
    const first = (await food.createCustomFood(userId, dto)) as { id: string };
    store.idempotency.clear();

    const recovered = (await food.createCustomFood(userId, dto)) as { id: string };
    expect(recovered.id).toBe(first.id);
    expect(store.customFoods.size).toBe(1);
    expect(store.idempotency.size).toBe(1);

    store.idempotency.clear();
    await expect(
      food.createCustomFood(userId, {
        ...dto,
        per100g: { ...dto.per100g, kcal: 61 },
      }),
    ).rejects.toThrow(
      expect.objectContaining({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' }) as unknown as Error,
    );
    expect(store.customFoods.size).toBe(1);
    expect(store.idempotency.size).toBe(0);
  });

  it('contribute 同键并发及回执缺失恢复都复用首次候选', async () => {
    const custom = (await food.createCustomFood(userId, createDto())) as { id: string };
    store.idempotency.clear();
    const dto = { clientRequestId: randomUUID() };
    const [first, replay] = await Promise.all([
      food.contributeCustomFood(userId, custom.id, dto),
      food.contributeCustomFood(userId, custom.id, dto),
    ]);
    expect(replay).toEqual(first);
    expect(store.foodCandidates.size).toBe(1);
    expect(store.idempotency.size).toBe(1);

    store.idempotency.clear();
    const recovered = (await food.contributeCustomFood(userId, custom.id, dto)) as { id: string };
    expect(recovered.id).toBe((first as { id: string }).id);
    expect(store.foodCandidates.size).toBe(1);
    expect(store.idempotency.size).toBe(1);
  });

  it('contribute 不同请求键并发同食物不堆重复候选', async () => {
    const custom = (await food.createCustomFood(userId, createDto())) as { id: string };
    store.idempotency.clear();
    const [first, second] = await Promise.all([
      food.contributeCustomFood(userId, custom.id, { clientRequestId: randomUUID() }),
      food.contributeCustomFood(userId, custom.id, { clientRequestId: randomUUID() }),
    ]);
    expect((second as { id: string }).id).toBe((first as { id: string }).id);
    expect(store.foodCandidates.size).toBe(1);
    expect(store.idempotency.size).toBe(2);
  });
});
