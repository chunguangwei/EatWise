import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import {
  CustomFoodEntity,
  DataStore,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodEntity,
} from '../common/store/data-store';
import { newId, payloadHash } from '../common/utils/id.util';
import { ContentModerationService } from '../social/moderation/content-moderation.service';
import { ContributeFoodDto, CreateCustomFoodDto, ReviewFoodCandidateDto } from './food.dto';
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
  constructor(
    private readonly store: DataStore,
    private readonly moderation: ContentModerationService,
  ) {}

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

  /**
   * 贡献自定义食物为共享候选（食物库扩充第三层，先审后发 D-17）。
   * - 只能贡献自己的自定义食物（他人的/不存在的 → 404，不泄露存在性）；
   * - 幂等：clientRequestId 重放返回首次结果（不同体 409）；同一食物已有候选时直接返回原状态；
   * - 食物名过机审：rejected → 拒收 FOOD_CONTRIBUTE_REJECTED；manual → 仍入池，状态 pending 转人工。
   */
  async contributeCustomFood(userId: string, foodId: string, dto: ContributeFoodDto) {
    const endpoint = 'foods/custom/contribute';
    const hash = payloadHash({ foodId });
    const idemKey = this.store.idemKey(userId, endpoint, dto.clientRequestId);
    const hit = this.store.idempotency.get(idemKey);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const food = this.store.customFoods.get(foodId);
    if (!food || food.userId !== userId) throw err.notFound();

    // 同一食物只允许一个候选：重复贡献幂等返回原状态（pending/approved/rejected）
    const existing = [...this.store.foodCandidates.values()].find((c) => c.foodId === foodId);
    if (existing) {
      const response = this.candidateView(existing);
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

    const verdict = await this.moderation.moderate(food.nameZh, []);
    if (verdict.verdict === 'rejected') {
      throw err.foodContributeRejected(verdict.reason);
    }

    const now = new Date();
    const candidate: FoodCandidateEntity = {
      id: `fc_${newId().slice(0, 8)}`,
      foodId,
      userId,
      status: 'pending', // manual 与 approved 机审结果均先入 pending 池，由人工终审晋升
      reason: null,
      clientRequestId: dto.clientRequestId,
      version: 1,
      createdAt: now,
      updatedAt: now,
    };
    this.store.foodCandidates.set(candidate.id, candidate);

    const response = this.candidateView(candidate);
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

  /** 管理端：审核队列（游标分页，createdAt 升序先入先审；status 过滤） */
  listFoodCandidates(status: FoodCandidateStatus | undefined, limit = 20, cursor?: string) {
    if (limit > 50) limit = 50;
    let offset = 0;
    if (cursor) {
      try {
        offset = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8')).offset ?? 0;
      } catch {
        throw err.invalidCursor();
      }
    }
    const all = [...this.store.foodCandidates.values()]
      .filter((c) => !status || c.status === status)
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime() || a.id.localeCompare(b.id));
    const page = all.slice(offset, offset + limit);
    const nextOffset = offset + limit;
    return {
      items: page.map((c) => this.candidateView(c)),
      pageInfo: {
        nextCursor:
          nextOffset < all.length
            ? Buffer.from(JSON.stringify({ offset: nextOffset })).toString('base64')
            : null,
        hasMore: nextOffset < all.length,
      },
    };
  }

  /**
   * 管理端：审核候选。
   * approve → 自定义食物晋升为共享食物（原 id 不变，isCustom=false 入共享库，全用户 K1 可见，
   * source='community'，createdByUserId 保留溯源）；reject → 状态 rejected + reason，
   * 创建者仍可见自己的自定义食物。
   */
  reviewFoodCandidate(candidateId: string, dto: ReviewFoodCandidateDto) {
    const candidate = this.store.foodCandidates.get(candidateId);
    if (!candidate) throw err.notFound();
    if (candidate.status !== 'pending') {
      throw err.conflict({ status: candidate.status });
    }
    candidate.updatedAt = new Date();
    candidate.version += 1;

    if (dto.action === 'reject') {
      candidate.status = 'rejected';
      candidate.reason = dto.reason?.trim() || null;
      return this.candidateView(candidate);
    }

    const custom = this.store.customFoods.get(candidate.foodId);
    if (!custom) throw err.notFound(); // 食物已被删除等异常态
    const shared: FoodEntity = {
      id: custom.id, // 保留原 id：既有 FoodEntry 引用不断链
      nameZh: custom.nameZh,
      nameEn: custom.nameEn,
      aliases: custom.aliases,
      kcalPer100g: custom.kcalPer100g,
      proteinPer100g: custom.proteinPer100g,
      carbsPer100g: custom.carbsPer100g,
      fatPer100g: custom.fatPer100g,
      category: '社区共享',
      source: 'community',
      createdByUserId: custom.userId,
    };
    this.store.customFoods.delete(custom.id);
    this.store.foods.set(shared.id, shared);
    candidate.status = 'approved';
    candidate.reason = null;
    return this.candidateView(candidate);
  }

  private candidateView(c: FoodCandidateEntity) {
    const food = this.store.customFoods.get(c.foodId) ?? this.store.foods.get(c.foodId);
    return {
      id: c.id,
      foodId: c.foodId,
      userId: c.userId,
      status: c.status,
      reason: c.reason,
      nameZh: food?.nameZh ?? null,
      nameEn: food?.nameEn ?? null,
      createdAt: c.createdAt.toISOString(),
      updatedAt: c.updatedAt.toISOString(),
    };
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
      source: f.source,
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
