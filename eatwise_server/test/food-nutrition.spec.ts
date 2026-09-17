import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { FoodService } from '../src/food/food.service';
import {
  computeSignals,
  computeTargets,
  computeWeightLossPlan,
} from '../src/nutrition/nutrition.rules';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

describe('K1 食物双语搜索（D-16）', () => {
  let food: FoodService;

  beforeEach(() => {
    food = new FoodService(new MemoryStoreDriver(new DataStore()), new StubModerationService());
  });

  it('拼音/别名匹配：q=ji 命中鸡蛋与鸡胸肉别名（matchedOn=alias）', async () => {
    const res = await food.search('ji');
    const names = res.items.map((i) => i.nameZh);
    expect(names).toContain('鸡蛋');
    expect(names).toContain('鸡胸肉');
    const egg = res.items.find((i) => i.nameZh === '鸡蛋')!;
    expect(egg.matchedOn).toBe('alias');
    expect(egg.highlight).toEqual({ field: 'aliases', text: 'ji dan' });
  });

  it('中文前缀匹配优先于别名（q=鸡：鸡胸肉/鸡蛋 nameZh 前缀，score 高于别名命中）', async () => {
    const res = await food.search('鸡');
    expect(res.items.length).toBeGreaterThanOrEqual(2);
    expect(res.items[0].matchedOn).toBe('nameZh');
    expect(res.items[0].highlight.field).toBe('nameZh');
  });

  it('英文大小写不敏感：q=EGG 命中 nameEn', async () => {
    const res = await food.search('EGG');
    const egg = res.items.find((i) => i.nameZh === '鸡蛋')!;
    expect(egg.matchedOn).toBe('nameEn');
  });

  it('前缀 > 子串 > 别名 排序', async () => {
    const res = await food.search('egg');
    // nameEn 前缀 'Egg'（score 3）应排在 'boiled egg' 别名子串（score 1）之前
    expect(res.items[0].nameEn).toBe('Egg');
  });

  it('无命中返回空数组', async () => {
    const res = await food.search('zzzz');
    expect(res.items).toEqual([]);
    expect(res.pageInfo.hasMore).toBe(false);
  });

  it('非法 limit（负数/NaN/小数）回落默认分页，不报错不死循环', async () => {
    for (const limit of [-5, Number.NaN, 0]) {
      const res = await food.search('鸡', limit);
      expect(res.items.length).toBeGreaterThanOrEqual(1);
      expect(res.pageInfo.hasMore).toBe(false); // 数据量小，默认页即可装下
    }
  });

  it('cursor offset 非负整数校验：负数/非整数 → 400 INVALID_CURSOR', async () => {
    const bad = (offset: unknown) => Buffer.from(JSON.stringify({ offset })).toString('base64');
    for (const cursor of [bad(-1), bad(1.5), bad('5')]) {
      await expect(food.search('鸡', 20, cursor)).rejects.toThrow(
        expect.objectContaining({ code: 'INVALID_CURSOR' }) as unknown as Error,
      );
    }
  });
});

describe('营养目标（D-04）与信号灯（D-05）', () => {
  it('缺基础信息 → 兜底值 + fallback 标记', () => {
    const t = computeTargets({
      gender: null,
      birthYear: null,
      heightCm: null,
      weightKg: null,
      activityLevel: null,
      goal: null,
      targetWeightKg: null,
      targetDate: null,
    });
    expect(t.fallback).toBe(true);
    expect(t.kcal).toBe(2000); // 性别未知兜底 2000（与客户端口径一致，规格 §1.6）
  });

  it('缺基础信息兜底：女 1800 / 男 2200 / 性别未知 2000', () => {
    const base = {
      birthYear: null,
      heightCm: null,
      weightKg: null,
      activityLevel: null,
      goal: null,
      targetWeightKg: null,
      targetDate: null,
    };
    expect(computeTargets({ ...base, gender: 'female' }).kcal).toBe(1800);
    expect(computeTargets({ ...base, gender: 'male' }).kcal).toBe(2200);
    expect(computeTargets({ ...base, gender: null }).kcal).toBe(2000);
  });

  it('减脂目标下限保护：女 ≥1200 / 男 ≥1500', () => {
    const t = computeTargets({
      gender: 'female',
      birthYear: 1998,
      heightCm: 150,
      weightKg: 40,
      activityLevel: 'sedentary',
      goal: 'fat_loss',
      targetWeightKg: null,
      targetDate: null,
    });
    expect(t.fallback).toBe(false);
    expect(t.kcal).toBeGreaterThanOrEqual(1200);
    // 供能比：蛋白 25% / 碳水 45% / 脂肪 30%
    expect(t.proteinG).toBe(Math.round((t.kcal * 0.25) / 4));
    expect(t.carbsG).toBe(Math.round((t.kcal * 0.45) / 4));
    expect(t.fatG).toBe(Math.round((t.kcal * 0.3) / 9));
  });

  it('信号灯：热量 91% → green；蛋白 62% → red；黄区边界', () => {
    const signals = computeSignals(
      { kcal: 1450, proteinG: 62, carbsG: 150, fatG: 48 },
      { kcal: 1600, proteinG: 100, carbsG: 200, fatG: 53, fallback: false },
    );
    const by = (n: string) => signals.find((s) => s.nutrient === n)!;
    expect(by('kcal').level).toBe('green'); // 91%
    expect(by('protein').level).toBe('red'); // 62% < 70%
    expect(by('carbs').level).toBe('yellow'); // 75% ∈ [65,85)
    expect(by('fat').level).toBe('green'); // 91%
    expect(by('kcal').adviceKey).toBe('advice.kcal.ok');
  });

  it('偏高黄灯方向修正：kcal 120% → advice.kcal.high（吃多了，而非 low）', () => {
    const signals = computeSignals(
      { kcal: 1920, proteinG: 160, carbsG: 240, fatG: 37 },
      { kcal: 1600, proteinG: 100, carbsG: 200, fatG: 53, fallback: false },
    );
    const by = (n: string) => signals.find((s) => s.nutrient === n)!;
    expect(by('kcal').level).toBe('yellow'); // 120% ∈ [110,130)
    expect(by('kcal').adviceKey).toBe('advice.kcal.high');
    expect(by('carbs').level).toBe('yellow'); // 120% ∈ [115,135)
    expect(by('carbs').adviceKey).toBe('advice.carbs.high');
    expect(by('protein').level).toBe('red'); // 160% > 150%
    expect(by('protein').adviceKey).toBe('advice.protein.high');
    expect(by('fat').level).toBe('yellow'); // 70% ∈ [55,80) 偏低
    expect(by('fat').adviceKey).toBe('advice.fat.low');
  });
});

describe('阶段 B 减重速率→热量缺口（computeWeightLossPlan，叠加 D-04）', () => {
  const now = new Date(Date.UTC(2026, 8, 17)); // 2026-09-17 UTC
  const dateInDays = (days: number) => new Date(now.getTime() + days * 86400000);

  it('正常缺口：70→65 kg / 70 天 → 0.5 kg/周，日缺口 550 kcal', () => {
    const plan = computeWeightLossPlan({
      currentWeightKg: 70,
      targetWeightKg: 65,
      targetDate: dateInDays(70),
      tdee: 2000,
      minKcal: 1200,
      now,
    })!;
    expect(plan.weeklyRateKg).toBeCloseTo(0.5, 6);
    expect(plan.dailyDeficitKcal).toBeCloseTo(550, 6); // 0.5 × 7700 ÷ 7
    expect(plan.targetKcal).toBeCloseTo(1450, 6);
    expect(plan.clamped).toBe(false);
    expect(plan.reachDate).toBe(dateInDays(70).toISOString().slice(0, 10));
  });

  it('超安全上限 clamp：60→50 kg / 28 天 → 夹取 1.0 kg/周并标记 clamped，达成日后移', () => {
    const plan = computeWeightLossPlan({
      currentWeightKg: 60,
      targetWeightKg: 50,
      targetDate: dateInDays(28),
      tdee: 2200,
      minKcal: 1500,
      now,
    })!;
    expect(plan.weeklyRateKg).toBe(1.0);
    expect(plan.dailyDeficitKcal).toBeCloseTo(1100, 6);
    // 2200 − 1100 = 1100 < 1500 → 下限保护到 1500（不破既有下限）
    expect(plan.targetKcal).toBe(1500);
    expect(plan.clamped).toBe(true);
    expect(plan.reachDate).toBe(dateInDays(70).toISOString().slice(0, 10)); // 10kg ÷ 1kg/周
  });

  it('下限保护：缺口法结果不破 minKcal', () => {
    const plan = computeWeightLossPlan({
      currentWeightKg: 60,
      targetWeightKg: 55,
      targetDate: dateInDays(35),
      tdee: 2000,
      minKcal: 1200,
      now,
    })!;
    expect(plan.weeklyRateKg).toBe(1.0); // 5kg/5周 = 1.0 恰好不 clamp
    expect(plan.clamped).toBe(false);
    expect(plan.targetKcal).toBe(1200); // 2000 − 1100 = 900 → 下限 1200
  });

  it('速率下限：极缓目标夹取到 0.1 kg/周', () => {
    const plan = computeWeightLossPlan({
      currentWeightKg: 60,
      targetWeightKg: 59,
      targetDate: dateInDays(365),
      tdee: 2000,
      minKcal: 1200,
      now,
    })!;
    expect(plan.weeklyRateKg).toBe(0.1);
    expect(plan.clamped).toBe(false);
  });

  it('不生效场景返回 null：无目标 / 目标≥当前 / 目标日期非未来', () => {
    const base = { currentWeightKg: 60, tdee: 2000, minKcal: 1200, now };
    expect(
      computeWeightLossPlan({ ...base, targetWeightKg: null, targetDate: dateInDays(30) }),
    ).toBeNull();
    expect(computeWeightLossPlan({ ...base, targetWeightKg: 55, targetDate: null })).toBeNull();
    expect(
      computeWeightLossPlan({ ...base, targetWeightKg: 60, targetDate: dateInDays(30) }),
    ).toBeNull();
    expect(
      computeWeightLossPlan({ ...base, targetWeightKg: 70, targetDate: dateInDays(30) }),
    ).toBeNull();
    expect(computeWeightLossPlan({ ...base, targetWeightKg: 55, targetDate: now })).toBeNull();
    expect(
      computeWeightLossPlan({ ...base, targetWeightKg: 55, targetDate: dateInDays(-1) }),
    ).toBeNull();
  });

  it('computeTargets 叠加：fat_loss + 目标体重+日期 → 缺口法；无目标 → 仍 TDEE×0.8', () => {
    // 女 1998 生 / 162cm / 55kg / 久坐：BMR 1261.5，TDEE 1513.8
    const base = {
      gender: 'female',
      birthYear: 1998,
      heightCm: 162,
      weightKg: 55,
      activityLevel: 'sedentary',
      goal: 'fat_loss',
    };
    const fixed = computeTargets({ ...base, targetWeightKg: null, targetDate: null });
    expect(fixed.weightLoss).toBeUndefined();
    expect(fixed.kcal).toBe(Math.round(1513.8 * 0.8)); // 1211

    // 55→53 kg / 28 天：0.5 kg/周 → 缺口 550 → 1513.8−550=963.8 → 下限 1200
    const deficit = computeTargets({
      ...base,
      targetWeightKg: 53,
      targetDate: new Date(Date.now() + 28 * 86400000),
    });
    expect(deficit.weightLoss).toBeDefined();
    expect(deficit.weightLoss!.weeklyRateKg).toBeCloseTo(0.5, 1);
    expect(deficit.kcal).toBe(1200); // 下限保护兜底

    // 目标≥当前 → 回落固定 ×0.8
    const maintain = computeTargets({
      ...base,
      targetWeightKg: 60,
      targetDate: new Date(Date.now() + 28 * 86400000),
    });
    expect(maintain.weightLoss).toBeUndefined();
    expect(maintain.kcal).toBe(1211);
  });
});
