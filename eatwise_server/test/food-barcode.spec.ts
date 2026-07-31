import { BarcodeService } from '../src/food/barcode/barcode.service';

/** OFF v2 正常响应（nutriments 给 energy-kcal_100g） */
function offProduct(overrides: Record<string, unknown> = {}) {
  return {
    status: 1,
    product: {
      product_name: 'Oreo Original',
      product_name_zh: '奥利奥原味夹心饼干',
      nutriments: {
        'energy-kcal_100g': 480,
        proteins_100g: 4.7,
        carbohydrates_100g: 68.5,
        fat_100g: 20.4,
      },
      ...overrides,
    },
  };
}

function mockFetch(body: unknown, ok = true): typeof fetch {
  return (() =>
    Promise.resolve({
      ok,
      json: () => Promise.resolve(body),
    } as Response)) as unknown as typeof fetch;
}

describe('BarcodeService（OFF 条码查询）', () => {
  it('命中：中文名优先，kcal 直取 energy-kcal_100g，id=off_{code}', async () => {
    const svc = new BarcodeService({ fetchFn: mockFetch(offProduct()) });
    const view = await svc.lookup('7622210449283');
    expect(view).toMatchObject({
      id: 'off_7622210449283',
      barcode: '7622210449283',
      nameZh: '奥利奥原味夹心饼干',
      nameEn: 'Oreo Original',
      kcalPer100g: 480,
      proteinPer100g: 4.7,
      carbsPer100g: 68.5,
      fatPer100g: 20.4,
      source: 'openfoodfacts',
      isCustom: false,
    });
  });

  it('能量只有 kJ 时按 4.184 换算 kcal〔假设〕', async () => {
    const svc = new BarcodeService({
      fetchFn: mockFetch(
        offProduct({
          nutriments: {
            'energy-kj_100g': 2008.32, // = 480 kcal
            proteins_100g: 4.7,
            carbohydrates_100g: 68.5,
            fat_100g: 20.4,
          },
        }),
      ),
    });
    const view = await svc.lookup('7622210449283');
    expect(view.kcalPer100g).toBe(480);
  });

  it('无中文名时 nameZh 回退通用 product_name〔假设〕', async () => {
    const svc = new BarcodeService({
      fetchFn: mockFetch(offProduct({ product_name_zh: undefined })),
    });
    const view = await svc.lookup('7622210449283');
    expect(view.nameZh).toBe('Oreo Original');
    expect(view.nameEn).toBe('Oreo Original');
  });

  it('缺营养字段 → 404 FOOD_BARCODE_NOT_FOUND（缺字段拒绝）', async () => {
    const svc = new BarcodeService({
      fetchFn: mockFetch(
        offProduct({
          nutriments: { 'energy-kcal_100g': 480, proteins_100g: 4.7 },
        }),
      ),
    });
    await expect(svc.lookup('7622210449283')).rejects.toMatchObject({
      code: 'FOOD_BARCODE_NOT_FOUND',
    });
  });

  it('营养越界（kcal>900）→ 404', async () => {
    const svc = new BarcodeService({
      fetchFn: mockFetch(
        offProduct({
          nutriments: {
            'energy-kcal_100g': 1200,
            proteins_100g: 4.7,
            carbohydrates_100g: 68.5,
            fat_100g: 20.4,
          },
        }),
      ),
    });
    await expect(svc.lookup('7622210449283')).rejects.toMatchObject({
      code: 'FOOD_BARCODE_NOT_FOUND',
    });
  });

  it('OFF 无该商品（status=0）→ 404', async () => {
    const svc = new BarcodeService({ fetchFn: mockFetch({ status: 0 }) });
    await expect(svc.lookup('0000000000000')).rejects.toMatchObject({
      code: 'FOOD_BARCODE_NOT_FOUND',
    });
  });

  it('OFF 超时/网络异常 → 404（降级口径一致）', async () => {
    const failing = (() => Promise.reject(new Error('aborted'))) as unknown as typeof fetch;
    const svc = new BarcodeService({ fetchFn: failing });
    await expect(svc.lookup('7622210449283')).rejects.toMatchObject({
      code: 'FOOD_BARCODE_NOT_FOUND',
    });
  });

  it('缓存命中：同一条码第二次查询不再请求 OFF', async () => {
    let calls = 0;
    const counting = (() => {
      calls += 1;
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(offProduct()),
      } as Response);
    }) as unknown as typeof fetch;
    const svc = new BarcodeService({ fetchFn: counting });
    await svc.lookup('7622210449283');
    await svc.lookup('7622210449283');
    expect(calls).toBe(1);
  });

  it('缓存过期后重新请求 OFF', async () => {
    let calls = 0;
    const counting = (() => {
      calls += 1;
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(offProduct()),
      } as Response);
    }) as unknown as typeof fetch;
    const svc = new BarcodeService({ fetchFn: counting, cacheTtlMs: -1 });
    await svc.lookup('7622210449283');
    await svc.lookup('7622210449283');
    expect(calls).toBe(2);
  });

  it.each([
    ['短于 8 位', '1234567'],
    ['长于 14 位', '123456789012345'],
    ['含字母', '7622210449ABC'],
    ['空串', '   '],
  ])('条码校验：%s → VALIDATION_ERROR', async (_label, code) => {
    const svc = new BarcodeService({ fetchFn: mockFetch(offProduct()) });
    await expect(svc.lookup(code)).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
  });

  it('EAN-8（8 位）与 14 位条码均合法', async () => {
    const svc = new BarcodeService({ fetchFn: mockFetch(offProduct()) });
    await expect(svc.lookup('12345670')).resolves.toMatchObject({
      barcode: '12345670',
    });
    await expect(svc.lookup('12345678901234')).resolves.toMatchObject({
      barcode: '12345678901234',
    });
  });
});
