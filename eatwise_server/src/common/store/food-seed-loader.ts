import * as fs from 'fs';
import * as path from 'path';
import { DataStore, FoodEntity } from './data-store';

/**
 * D-16 食物库 seed 加载入口（内存 DataStore 版）。
 *
 * 读取 eatwise_data/foods.seed.json（统一中间格式，见 eatwise_data/README.md），
 * 合并进 DataStore.foods；与构造函数内置的演示 fixture 共存（id 前缀
 * curated-/usda- 与 fixture 的 f_ 前缀不冲突）。
 *
 * 幂等：同一 DataStore 实例重复调用时按已加载版本号跳过。
 * 接入真实 PostgreSQL 后由 prisma/seed.ts 承担等价职责。
 */

interface SeedFood {
  id: string;
  name_en: string;
  name_zh: string | null;
  aliases_zh?: string[];
  aliases_en?: string[];
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  category?: string;
  source: string;
}

interface SeedDoc {
  version: string;
  foods: SeedFood[];
}

export interface FoodSeedLoadResult {
  version: string;
  /** 本次新写入的条目数（skipped=true 时为 0）。 */
  loaded: number;
  skipped: boolean;
}

/** 默认 seed 路径：server 以 eatwise_server/ 为 cwd 运行（npm run start:dev）。 */
export function defaultFoodSeedPath(): string {
  return path.resolve(process.cwd(), '..', 'eatwise_data', 'foods.seed.json');
}

/**
 * 加载 foods.seed.json 到内存库。文件不存在返回 null（静默降级，
 * 构造函数内置 fixture 仍保证 K1/K2 搜索有数据）。
 */
export function loadFoodSeedFromFile(
  store: DataStore,
  seedPath: string = defaultFoodSeedPath(),
): FoodSeedLoadResult | null {
  if (store.foodSeedVersion) {
    return { version: store.foodSeedVersion, loaded: 0, skipped: true };
  }
  if (!fs.existsSync(seedPath)) {
    return null;
  }
  const doc = JSON.parse(fs.readFileSync(seedPath, 'utf8')) as SeedDoc;
  for (const f of doc.foods) {
    const entity: FoodEntity = {
      id: f.id,
      // 双语条目 nameZh 必有值；USDA 未翻译条目（zh_verified=false）回退空串，
      // 中文搜索由双语别名兜底（规格-i18n §四：缺译条目有回退而非空白）。
      nameZh: f.name_zh ?? '',
      nameEn: f.name_en,
      aliases: [...(f.aliases_zh ?? []), ...(f.aliases_en ?? [])],
      kcalPer100g: f.kcal,
      proteinPer100g: f.protein_g,
      carbsPer100g: f.carb_g,
      fatPer100g: f.fat_g,
      category: f.category ?? '',
      source: f.source,
    };
    store.foods.set(entity.id, entity);
  }
  store.foodSeedVersion = doc.version;
  return { version: doc.version, loaded: doc.foods.length, skipped: false };
}
