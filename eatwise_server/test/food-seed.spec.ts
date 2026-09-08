import * as path from 'path';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { loadFoodSeedFromFile } from '../src/common/store/food-seed-loader';
import { FoodService } from '../src/food/food.service';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';

/**
 * D-16 全量食物库（eatwise_data/foods.seed.json）灌入内存 DataStore 后的
 * K1/K2 双语搜索验证。seed 文件由 eatwise_data 管线生成（见该目录 README）。
 */
describe('D-16 全量食物库 seed 加载与双语搜索', () => {
  const seedPath = path.resolve(__dirname, '..', '..', 'eatwise_data', 'foods.seed.json');
  let store: DataStore;
  let food: FoodService;

  beforeAll(() => {
    store = new DataStore();
    food = new FoodService(new MemoryStoreDriver(store), new StubModerationService());
  });

  it('加载 seed：>=7000 条，含 USDA 与策展来源', () => {
    const result = loadFoodSeedFromFile(store, seedPath);
    expect(result).not.toBeNull();
    expect(result!.skipped).toBe(false);
    expect(result!.loaded).toBeGreaterThanOrEqual(7000);
    const sources = new Set([...store.foods.values()].map((f) => f.source));
    expect(sources).toContain('usda-sr');
    expect(sources).toContain('curated');
  });

  it('幂等：同实例重复加载按版本号跳过', () => {
    const before = store.foods.size;
    const result = loadFoodSeedFromFile(store, seedPath);
    expect(result!.skipped).toBe(true);
    expect(result!.loaded).toBe(0);
    expect(store.foods.size).toBe(before);
  });

  it('K1 中文词命中中文名：q=米饭 命中 nameZh', async () => {
    const res = await food.search('米饭');
    expect(res.items.length).toBeGreaterThan(0);
    expect(res.items[0].nameZh).toContain('米饭');
    expect(res.items[0].matchedOn).toBe('nameZh');
  });

  it('K2 英文词命中中文食物（别名兜底）：q=grilled chicken breast 命中鸡胸肉', async () => {
    // 注：泛词 'chicken' 在 USDA 全量库有 387+ 条 nameEn 前缀/子串命中，
    // 别名命中的中文条目按契约排序（前缀>子串>别名）不进首页，属预期行为；
    // 双语别名匹配能力用具体词组验证。
    const res = await food.search('grilled chicken breast');
    const breast = res.items.find((i) => i.nameZh === '鸡胸肉');
    expect(breast).toBeDefined();
    expect(breast!.matchedOn).toBe('alias');
    expect(breast!.kcalPer100g).toBeGreaterThan(0);
  });

  it('K2 中文词命中英文条目：q=鸡胸 跨语言可检索', async () => {
    const res = await food.search('鸡胸');
    expect(res.items.some((i) => i.nameZh === '鸡胸肉')).toBe(true);
  });

  it('USDA 条目可检索且营养字段齐全：q=rice 有结果', async () => {
    const res = await food.search('rice');
    expect(res.items.length).toBeGreaterThan(0);
    const hit = res.items[0];
    expect(hit.kcalPer100g).toBeGreaterThanOrEqual(0);
    expect(hit.proteinPer100g).toBeGreaterThanOrEqual(0);
  });
});
