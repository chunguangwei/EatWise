import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { CustomFoodEntity, DataStore, FoodEntity } from '../common/store/data-store';
import { newId, payloadHash } from '../common/utils/id.util';
import { CreateCustomFoodDto } from './food.dto';
import { isPer100gInRange } from './food.rules';

export interface FoodSearchHit {
  food: FoodEntity | CustomFoodEntity;
  isCustom: boolean;
  score: number;
  matchedOn: 'nameZh' | 'nameEn' | 'alias';
  highlight: { field: string; text: string };
}

@Injectable()
export class FoodService {
  constructor(private readonly store: DataStore) {}

  /** 内置库 + 个人自定义库（自定义仅创建者可见） */
  getById(id: string, userId?: string): FoodEntity | CustomFoodEntity | undefined {
    const builtIn = this.store.foods.get(id);
    if (builtIn) return builtIn;
    const custom = this.store.customFoods.get(id);
    if (!custom) return undefined;
    return userId && custom.userId === userId ? custom : undefined;
  }

  /**
   * K1 双语搜索：q 同时匹配 nameZh / nameEn / aliases，大小写不敏感；
   * 排序优先级 前缀 > 子串 > 别名（契约 §3.6）。中英文混合输入原样匹配（不翻译）。
   * 自定义食物（仅创建者可见）排在内置结果之后，标注 isCustom。
   */
  search(q: string, limit = 20, cursor?: string, userId?: string) {
    if (limit > 50) limit = 50;
    let offset = 0;
    if (cursor) {
      try {
        offset = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8')).offset ?? 0;
      } catch {
        throw err.invalidCursor();
      }
    }
    const hits = this.matchAll(q, userId);
    const page = hits.slice(offset, offset + limit);
    const nextOffset = offset + limit;
    return {
      items: page.map((h) => this.hitView(h)),
      pageInfo: {
        nextCursor:
          nextOffset < hits.length
            ? Buffer.from(JSON.stringify({ offset: nextOffset })).toString('base64')
            : null,
        hasMore: nextOffset < hits.length,
      },
    };
  }

  /** 创建自定义食物（幂等：clientRequestId 重放返回首次结果，不同体 409） */
  createCustomFood(userId: string, dto: CreateCustomFoodDto) {
    const endpoint = 'foods/custom';
    const hash = payloadHash({
      nameZh: dto.nameZh,
      nameEn: dto.nameEn ?? null,
      per100g: dto.per100g,
      source: dto.source,
    });
    const idemKey = this.store.idemKey(userId, endpoint, dto.clientRequestId);
    const hit = this.store.idempotency.get(idemKey);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const nameZh = dto.nameZh.trim();
    if (nameZh.length < 1 || nameZh.length > 50) {
      throw err.validation({ nameZh: 'trimmed length must be 1-50' });
    }
    if (!isPer100gInRange(dto.per100g)) {
      throw err.validation({ per100g: 'out of range (kcal 0-900, macros 0-100)' });
    }

    const food: CustomFoodEntity = {
      id: `cf_${newId().slice(0, 8)}`,
      userId,
      clientRequestId: dto.clientRequestId,
      nameZh,
      nameEn: dto.nameEn?.trim() || nameZh, // 〔假设〕未给英文名时回退中文名
      aliases: [...(dto.aliasesZh ?? []), ...(dto.aliasesEn ?? [])]
        .map((a) => a.trim())
        .filter(Boolean),
      kcalPer100g: dto.per100g.kcal,
      proteinPer100g: dto.per100g.proteinG,
      carbsPer100g: dto.per100g.carbG,
      fatPer100g: dto.per100g.fatG,
      source: dto.source,
      createdAt: new Date(),
    };
    this.store.customFoods.set(food.id, food);

    const response = this.customView(food);
    this.store.idempotency.set(idemKey, {
      userId,
      clientRequestId: dto.clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: new Date(),
    });
    return response;
  }

  private matchAll(q: string, userId?: string): FoodSearchHit[] {
    const ql = q.trim().toLowerCase();
    if (!ql) return [];
    const builtIn: FoodSearchHit[] = [];
    for (const food of this.store.foods.values()) {
      const hit = this.matchFood(food, q.trim(), ql, false);
      if (hit) builtIn.push(hit);
    }
    builtIn.sort((a, b) => b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh));
    // 自定义食物：仅创建者可见，整体排在内置结果之后（内部仍按匹配分排序）
    const custom: FoodSearchHit[] = [];
    if (userId) {
      for (const food of this.store.customFoods.values()) {
        if (food.userId !== userId) continue;
        const hit = this.matchFood(food, q.trim(), ql, true);
        if (hit) custom.push(hit);
      }
      custom.sort((a, b) => b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh));
    }
    return [...builtIn, ...custom];
  }

  private matchFood(
    food: FoodEntity | CustomFoodEntity,
    q: string,
    ql: string,
    isCustom: boolean,
  ): FoodSearchHit | null {
    // 前缀匹配优先（score 3），子串次之（score 2），别名最后（score 1）
    if (food.nameZh.includes(q)) {
      return {
        food,
        isCustom,
        score: food.nameZh.startsWith(q) ? 3 : 2,
        matchedOn: 'nameZh',
        highlight: { field: 'nameZh', text: food.nameZh },
      };
    }
    const en = food.nameEn.toLowerCase();
    if (en.includes(ql)) {
      return {
        food,
        isCustom,
        score: en.startsWith(ql) ? 3 : 2,
        matchedOn: 'nameEn',
        highlight: { field: 'nameEn', text: food.nameEn },
      };
    }
    const alias = food.aliases.find((a) => a.toLowerCase().includes(ql));
    if (alias) {
      return {
        food,
        isCustom,
        score: 1,
        matchedOn: 'alias',
        highlight: { field: 'aliases', text: alias },
      };
    }
    return null;
  }

  private hitView(h: FoodSearchHit) {
    const f = h.food;
    return {
      id: f.id,
      nameZh: f.nameZh,
      nameEn: f.nameEn,
      aliases: f.aliases,
      kcalPer100g: f.kcalPer100g,
      proteinPer100g: f.proteinPer100g,
      carbsPer100g: f.carbsPer100g,
      fatPer100g: f.fatPer100g,
      category: 'category' in f ? f.category : '自定义',
      isCustom: h.isCustom,
      matchedOn: h.matchedOn,
      highlight: h.highlight,
    };
  }

  private customView(f: CustomFoodEntity) {
    return {
      id: f.id,
      nameZh: f.nameZh,
      nameEn: f.nameEn,
      aliases: f.aliases,
      per100g: {
        kcal: f.kcalPer100g,
        proteinG: f.proteinPer100g,
        carbG: f.carbsPer100g,
        fatG: f.fatPer100g,
      },
      source: f.source,
      isCustom: true,
      createdAt: f.createdAt.toISOString(),
    };
  }
}
