import { DataStore } from '../src/common/store/data-store';
import { FoodService } from '../src/food/food.service';
import { computeSignals, computeTargets } from '../src/nutrition/nutrition.rules';

describe('K1 食物双语搜索（D-16）', () => {
  let food: FoodService;

  beforeEach(() => {
    food = new FoodService(new DataStore());
  });

  it('拼音/别名匹配：q=ji 命中鸡蛋与鸡胸肉别名（matchedOn=alias）', () => {
    const res = food.search('ji');
    const names = res.items.map((i) => i.nameZh);
    expect(names).toContain('鸡蛋');
    expect(names).toContain('鸡胸肉');
    const egg = res.items.find((i) => i.nameZh === '鸡蛋')!;
    expect(egg.matchedOn).toBe('alias');
    expect(egg.highlight).toEqual({ field: 'aliases', text: 'ji dan' });
  });

  it('中文前缀匹配优先于别名（q=鸡：鸡胸肉/鸡蛋 nameZh 前缀，score 高于别名命中）', () => {
    const res = food.search('鸡');
    expect(res.items.length).toBeGreaterThanOrEqual(2);
    expect(res.items[0].matchedOn).toBe('nameZh');
    expect(res.items[0].highlight.field).toBe('nameZh');
  });

  it('英文大小写不敏感：q=EGG 命中 nameEn', () => {
    const res = food.search('EGG');
    const egg = res.items.find((i) => i.nameZh === '鸡蛋')!;
    expect(egg.matchedOn).toBe('nameEn');
  });

  it('前缀 > 子串 > 别名 排序', () => {
    const res = food.search('egg');
    // nameEn 前缀 'Egg'（score 3）应排在 'boiled egg' 别名子串（score 1）之前
    expect(res.items[0].nameEn).toBe('Egg');
  });

  it('无命中返回空数组', () => {
    const res = food.search('zzzz');
    expect(res.items).toEqual([]);
    expect(res.pageInfo.hasMore).toBe(false);
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
    });
    expect(t.fallback).toBe(true);
    expect(t.kcal).toBe(1800); // 性别未知按女兜底
  });

  it('减脂目标下限保护：女 ≥1200 / 男 ≥1500', () => {
    const t = computeTargets({
      gender: 'female',
      birthYear: 1998,
      heightCm: 150,
      weightKg: 40,
      activityLevel: 'sedentary',
      goal: 'fat_loss',
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
});
