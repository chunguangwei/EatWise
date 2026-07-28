import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore, FoodEntity } from '../common/store/data-store';

export interface FoodSearchHit {
  food: FoodEntity;
  score: number;
  matchedOn: 'nameZh' | 'nameEn' | 'alias';
  highlight: { field: string; text: string };
}

@Injectable()
export class FoodService {
  constructor(private readonly store: DataStore) {}

  getById(id: string): FoodEntity | undefined {
    return this.store.foods.get(id);
  }

  /**
   * K1 双语搜索：q 同时匹配 nameZh / nameEn / aliases，大小写不敏感；
   * 排序优先级 前缀 > 子串 > 别名（契约 §3.6）。中英文混合输入原样匹配（不翻译）。
   */
  search(q: string, limit = 20, cursor?: string) {
    if (limit > 50) limit = 50;
    let offset = 0;
    if (cursor) {
      try {
        offset = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8')).offset ?? 0;
      } catch {
        throw err.invalidCursor();
      }
    }
    const hits = this.matchAll(q);
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

  private matchAll(q: string): FoodSearchHit[] {
    const ql = q.trim().toLowerCase();
    if (!ql) return [];
    const hits: FoodSearchHit[] = [];
    for (const food of this.store.foods.values()) {
      const hit = this.matchFood(food, q.trim(), ql);
      if (hit) hits.push(hit);
    }
    return hits.sort((a, b) => b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh));
  }

  private matchFood(food: FoodEntity, q: string, ql: string): FoodSearchHit | null {
    // 前缀匹配优先（score 3），子串次之（score 2），别名最后（score 1）
    if (food.nameZh.includes(q)) {
      return {
        food,
        score: food.nameZh.startsWith(q) ? 3 : 2,
        matchedOn: 'nameZh',
        highlight: { field: 'nameZh', text: food.nameZh },
      };
    }
    const en = food.nameEn.toLowerCase();
    if (en.includes(ql)) {
      return {
        food,
        score: en.startsWith(ql) ? 3 : 2,
        matchedOn: 'nameEn',
        highlight: { field: 'nameEn', text: food.nameEn },
      };
    }
    const alias = food.aliases.find((a) => a.toLowerCase().includes(ql));
    if (alias) {
      return {
        food,
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
      category: f.category,
      matchedOn: h.matchedOn,
      highlight: h.highlight,
    };
  }
}
