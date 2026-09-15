import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

/**
 * 条码商品众包回传（带营养表佐证照片）：贡献校验（格式/照片成对/机审）、
 * 同条码查重口径（pending 幂等返回已有 / approved 409 / rejected 不阻断）、
 * approve 晋升把 barcode 写入共享 Food 行。
 */
describe('条码商品贡献（FoodService.contributeCustomFood barcode 扩展）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;

  const USER = 'user_barcode_1';

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
  });

  async function createCustom(nameZh: string, userId = USER): Promise<string> {
    const created = (await food.createCustomFood(userId, {
      clientRequestId: randomUUID(),
      nameZh,
      per100g: { kcal: 200, proteinG: 8, carbG: 30, fatG: 6 },
      source: 'manual',
    })) as { id: string };
    return created.id;
  }

  interface CandidateView {
    id: string;
    foodId: string;
    status: string;
    kind: string;
    barcode: string | null;
    evidenceImageUrl: string | null;
    nameZh: string | null;
  }

  const contribute = async (
    foodId: string,
    extra: { barcode?: string; evidenceImageUrl?: string } = {},
    userId = USER,
  ): Promise<CandidateView> =>
    (await food.contributeCustomFood(userId, foodId, {
      clientRequestId: randomUUID(),
      ...extra,
    })) as CandidateView;

  it('条码贡献成功：kind=barcode，barcode/evidenceImageUrl 入候选视图，状态 pending', async () => {
    const foodId = await createCustom('条码饼干');
    const res = await contribute(foodId, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    });
    expect(res).toMatchObject({
      foodId,
      status: 'pending',
      kind: 'barcode',
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
      nameZh: '条码饼干',
    });
  });

  it('条码格式非法（<8 位 / 含字母 / >14 位）→ 400 VALIDATION_ERROR', async () => {
    const foodId = await createCustom('格式校验食品');
    for (const bad of ['1234567', '6901234567892345', '69012abc67892']) {
      await expect(
        contribute(foodId, { barcode: bad, evidenceImageUrl: '/v1/uploads/abc.jpg' }),
      ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    }
  });

  it('barcode 不带佐证照片 → 400；只传照片不传条码 → 400', async () => {
    const foodId = await createCustom('照片校验食品');
    await expect(contribute(foodId, { barcode: '6901234567892' })).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
      details: { fields: { evidenceImageUrl: 'required when barcode is present' } },
    });
    await expect(
      contribute(foodId, { evidenceImageUrl: '/v1/uploads/abc.jpg' }),
    ).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
      details: { fields: { barcode: 'required when evidenceImageUrl is present' } },
    });
  });

  it('机审 rejected（违规词）条码贡献同样拒收 FOOD_CONTRIBUTE_REJECTED', async () => {
    const foodId = await createCustom('赌博主题套餐');
    await expect(
      contribute(foodId, { barcode: '6901234567892', evidenceImageUrl: '/v1/uploads/abc.jpg' }),
    ).rejects.toMatchObject({ code: 'FOOD_CONTRIBUTE_REJECTED' });
  });

  it('同 barcode 已有 pending 候选（任意贡献者）→ 幂等返回已有候选，不产生第二条', async () => {
    const foodA = await createCustom('条码威化甲');
    const first = await contribute(foodA, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    });

    // 另一用户、另一食物、同条码
    const foodB = await createCustom('条码威化乙', 'user_barcode_2');
    const again = await contribute(
      foodB,
      { barcode: '6901234567892', evidenceImageUrl: '/v1/uploads/def.jpg' },
      'user_barcode_2',
    );
    expect(again.id).toBe(first.id);
    expect(again.status).toBe('pending');
    expect(store.foodCandidates.size).toBe(1);
  });

  it('同 barcode 已有 approved 候选 → 409 CONFLICT（已上架）', async () => {
    const foodA = await createCustom('已上架饼干');
    const first = await contribute(foodA, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    });
    await food.reviewFoodCandidate(first.id, { action: 'approve' });

    const foodB = await createCustom('重复上架饼干');
    await expect(
      contribute(foodB, { barcode: '6901234567892', evidenceImageUrl: '/v1/uploads/def.jpg' }),
    ).rejects.toMatchObject({ code: 'CONFLICT' });
  });

  it('同 barcode 已有 rejected 候选 → 不阻断，可重新提交', async () => {
    const foodA = await createCustom('被拒饼干甲');
    const first = await contribute(foodA, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    });
    await food.reviewFoodCandidate(first.id, { action: 'reject', reason: '照片看不清' });

    const foodB = await createCustom('被拒饼干乙');
    const retry = await contribute(foodB, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/clear.jpg',
    });
    expect(retry.id).not.toBe(first.id);
    expect(retry.status).toBe('pending');
  });

  it('approve 晋升：条码写入共享 Food 行（后续扫码可命中自有库）；普通贡献 barcode 为 null', async () => {
    const foodId = await createCustom('晋升条码薯片');
    const candidate = await contribute(foodId, {
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    });
    const approved = await food.reviewFoodCandidate(candidate.id, { action: 'approve' });
    expect(approved.status).toBe('approved');

    const shared = await driver.findFoodById(foodId);
    expect(shared).toMatchObject({ id: foodId, barcode: '6901234567892', source: 'community' });

    // 自定义贡献（无条码）晋升不带 barcode
    const customId = await createCustom('晋升家常菜');
    const customCandidate = await contribute(customId);
    expect(customCandidate.kind).toBe('custom');
    expect(customCandidate.barcode).toBeNull();
    await food.reviewFoodCandidate(customCandidate.id, { action: 'approve' });
    expect((await driver.findFoodById(customId))!.barcode).toBeNull();
  });

  it('幂等：同 clientRequestId 重放返回同一候选；同键不同条码体 → 409', async () => {
    const foodId = await createCustom('幂等条码糖');
    const reqId = randomUUID();
    const body = {
      clientRequestId: reqId,
      barcode: '6901234567892',
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    };
    const first = (await food.contributeCustomFood(USER, foodId, body)) as CandidateView;
    const replay = (await food.contributeCustomFood(USER, foodId, body)) as CandidateView;
    expect(replay.id).toBe(first.id);

    const other = await createCustom('幂等条码糖二');
    await expect(
      food.contributeCustomFood(USER, other, {
        clientRequestId: reqId,
        barcode: '6999999999999',
        evidenceImageUrl: '/v1/uploads/abc.jpg',
      }),
    ).rejects.toMatchObject({ code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' });
  });
});

/** 条码查询第一跳：自有共享库（条码众包上架后 GET /foods/barcode/:code 不再打 OFF） */
describe('条码查询自有库命中（FoodService.lookupOwnBarcode）', () => {
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let food: FoodService;

  const USER = 'user_barcode_lookup';

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    food = new FoodService(driver, new StubModerationService());
  });

  async function createAndContribute(barcode: string): Promise<string> {
    const created = (await food.createCustomFood(USER, {
      clientRequestId: randomUUID(),
      nameZh: '条码闭环饼干',
      per100g: { kcal: 480, proteinG: 4.7, carbG: 68.5, fatG: 20.4 },
      source: 'manual',
    })) as { id: string };
    const candidate = (await food.contributeCustomFood(USER, created.id, {
      clientRequestId: randomUUID(),
      barcode,
      evidenceImageUrl: '/v1/uploads/abc.jpg',
    })) as { id: string };
    return candidate.id;
  }

  it('approved 后命中自有库：source=eatwise、结构与 OFF 视图同构；pending 时不命中', async () => {
    const barcode = '6901234567892';
    const candidateId = await createAndContribute(barcode);

    // pending（尚未上架）：自有库不可见
    expect(await food.lookupOwnBarcode(barcode)).toBeNull();

    await food.reviewFoodCandidate(candidateId, { action: 'approve' });
    const hit = await food.lookupOwnBarcode(barcode);
    expect(hit).toEqual({
      id: expect.any(String),
      barcode,
      nameZh: '条码闭环饼干',
      nameEn: '条码闭环饼干',
      aliases: [],
      kcalPer100g: 480,
      proteinPer100g: 4.7,
      carbsPer100g: 68.5,
      fatPer100g: 20.4,
      source: 'eatwise',
      isCustom: false,
    });
  });

  it('格式非法 / 未上架条码 → null（由 OFF 路径承接）', async () => {
    expect(await food.lookupOwnBarcode('123')).toBeNull();
    expect(await food.lookupOwnBarcode('  ')).toBeNull();
    expect(await food.lookupOwnBarcode('6999999999999')).toBeNull();
  });

  it('code 首尾空白可命中（与 OFF 路径 trim 口径一致）', async () => {
    const barcode = '6901234567892';
    const candidateId = await createAndContribute(barcode);
    await food.reviewFoodCandidate(candidateId, { action: 'approve' });
    expect((await food.lookupOwnBarcode(` ${barcode} `))?.source).toBe('eatwise');
  });
});
