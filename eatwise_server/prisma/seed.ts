/**
 * D-16 食物库 PostgreSQL 种子脚本：把 eatwise_data/foods.seed.json 灌入 Food 表。
 *
 * 用法：
 *   npm run prisma:seed        # 等价于 `prisma db seed`
 *
 * 幂等：按 Food.id upsert，可重复执行；seed 内 id 为稳定 slug
 *（curated-* / usda-<fdcId>），重跑不会产生重复行。
 *
 * 前置：DATABASE_URL 已配置且 `prisma migrate dev` 已执行。
 * 内存 DataStore（无数据库的开发模式）的等价入口：
 * src/common/store/food-seed-loader.ts（main.ts 启动时自动调用）。
 */
import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

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
  counts: { total: number };
  /** 历史版本出现过、当前版本已删除的行 id（累计）——导入方按它清残差。 */
  removedIds?: string[];
  foods: SeedFood[];
}

const prisma = new PrismaClient();

async function main(): Promise<void> {
  const seedPath = path.resolve(__dirname, '..', '..', 'eatwise_data', 'foods.seed.json');
  const doc = JSON.parse(fs.readFileSync(seedPath, 'utf8')) as SeedDoc;
  console.log(`[seed] foods.seed.json v${doc.version}, ${doc.foods.length} entries`);

  let upserted = 0;
  const BATCH = 200;
  for (let i = 0; i < doc.foods.length; i += BATCH) {
    const batch = doc.foods.slice(i, i + BATCH);
    await prisma.$transaction(
      batch.map((f) => {
        const data = {
          // 双语条目 nameZh 必有值；USDA 未翻译条目回退英文名
          //（schema 要求非空；i18n 规格：缺译条目有回退而非空白）。
          nameZh: f.name_zh ?? f.name_en,
          nameEn: f.name_en,
          aliases: [...(f.aliases_zh ?? []), ...(f.aliases_en ?? [])],
          kcalPer100g: f.kcal,
          proteinPer100g: f.protein_g,
          carbsPer100g: f.carb_g,
          fatPer100g: f.fat_g,
          category: f.category ?? null,
          source: f.source,
        };
        return prisma.food.upsert({
          where: { id: f.id },
          create: { id: f.id, ...data },
          update: data,
        });
      }),
    );
    upserted += batch.length;
  }
  console.log(`[seed] done: ${upserted} foods upserted`);
  // seed 版本收敛：软删历史版本导入、本版已删除的行。软删而非硬删——
  // FoodEntry.foodId 外键无 onDelete，硬删会违约（v1.13.6 踩过）；
  // 读路径已统一过滤 deletedAt:null。isCustom=false 门：个人库行不受 seed 管治。
  const removedIds = doc.removedIds ?? [];
  if (removedIds.length > 0) {
    const { count } = await prisma.food.updateMany({
      where: { id: { in: removedIds }, isCustom: false, deletedAt: null },
      data: { deletedAt: new Date() },
    });
    console.log(`[seed] pruned ${count}/${removedIds.length} stale rows (soft delete)`);
  }
}

main()
  .catch((e) => {
    console.error('[seed] failed:', e);
    process.exitCode = 1;
  })
  .finally(() => {
    void prisma.$disconnect();
  });
