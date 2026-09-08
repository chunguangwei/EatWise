import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import {
  CustomFoodEntity,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodEntity,
} from '../common/store/data-store';
import { FoodSearchHit, STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { ContentModerationService } from '../social/moderation/content-moderation.service';
import { ContributeFoodDto, CreateCustomFoodDto, ReviewFoodCandidateDto } from './food.dto';
import { isPer100gInRange } from './food.rules';

/**
 * 食物库（D-16 内置库 + 个人自定义库 + D-17 众包候选审核池）。
 * 读写全部收口到 StoreDriver（prisma 模式真实落库）：搜索匹配、候选读路径、
 * 审核晋升（自定义行原子转共享）由驱动提供与内存同口径的实现。
 */
@Injectable()
export class FoodService {
  constructor(
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
    private readonly moderation: ContentModerationService,
  ) {}

  /** 内置库 + 个人自定义库（自定义仅创建者可见） */
  async getById(id: string, userId?: string): Promise<FoodEntity | CustomFoodEntity | undefined> {
    const builtIn = await this.driver.findFoodById(id);
    if (builtIn) return builtIn;
    const custom = await this.driver.findCustomFoodById(id);
    if (!custom) return undefined;
    return userId && custom.userId === userId ? custom : undefined;
  }

  /**
   * K1 双语搜索：q 同时匹配 nameZh / nameEn / aliases，大小写不敏感；
   * 排序优先级 前缀 > 子串 > 别名（契约 §3.6）。中英文混合输入原样匹配（不翻译）。
   * 自定义食物（仅创建者可见）排在内置结果之后，标注 isCustom。
   */
  async search(q: string, limit = 20, cursor?: string, userId?: string) {
    if (limit > 50) limit = 50;
    let offset = 0;
    if (cursor) {
      try {
        offset = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8')).offset ?? 0;
      } catch {
        throw err.invalidCursor();
      }
    }
    const hits = await this.driver.searchFoods(q, userId);
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
  async createCustomFood(userId: string, dto: CreateCustomFoodDto) {
    const endpoint = 'foods/custom';
    const hash = payloadHash({
      nameZh: dto.nameZh,
      nameEn: dto.nameEn ?? null,
      per100g: dto.per100g,
      source: dto.source,
    });
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
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
    await this.driver.createCustomFood(food);

    const response = this.customView(food);
    await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
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
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const food = await this.driver.findCustomFoodById(foodId);
    if (!food || food.userId !== userId) throw err.notFound();

    // 同一食物只允许一个候选：重复贡献幂等返回原状态（pending/approved/rejected）
    const existing = await this.driver.findFoodCandidateByFoodId(foodId);
    if (existing) {
      const response = await this.candidateView(existing);
      await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
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
    await this.driver.createFoodCandidate(candidate);

    const response = await this.candidateView(candidate);
    await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
    return response;
  }

  /** 管理端：审核队列（游标分页，createdAt 升序先入先审；status 过滤） */
  async listFoodCandidates(status: FoodCandidateStatus | undefined, limit = 20, cursor?: string) {
    if (limit > 50) limit = 50;
    let offset = 0;
    if (cursor) {
      try {
        offset = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8')).offset ?? 0;
      } catch {
        throw err.invalidCursor();
      }
    }
    const all = await this.driver.listFoodCandidates(status);
    const page = all.slice(offset, offset + limit);
    const nextOffset = offset + limit;
    return {
      items: await Promise.all(page.map((c) => this.candidateView(c))),
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
   * 用户端：我的贡献批量查询（众包状态列表）。只返回本人候选；
   * status 缺省返回全部状态；createdAt 降序（最新在前），页码分页（page 从 1 起）。
   * 返回精简视图（不含营养/名称——食物名由客户端按 foodId 本地解析）。
   */
  async findContributionsByUser(
    userId: string,
    status: FoodCandidateStatus | undefined,
    page = 1,
    pageSize = 20,
  ) {
    // 驱动侧按 (createdAt, id) 降序返回本人候选（最新在前）
    const all = await this.driver.findFoodCandidatesByUser(userId, status);
    const offset = (page - 1) * pageSize;
    return {
      items: all.slice(offset, offset + pageSize).map((c) => ({
        id: c.id,
        foodId: c.foodId,
        status: c.status,
        reason: c.reason,
        createdAt: c.createdAt.toISOString(),
        updatedAt: c.updatedAt.toISOString(),
      })),
      total: all.length,
      page,
      pageSize,
    };
  }

  /**
   * 管理端：审核候选。
   * approve → 自定义食物晋升为共享食物（原 id 不变，isCustom=false 入共享库，全用户 K1 可见，
   * source='community'，createdByUserId 保留溯源）；reject → 状态 rejected + reason，
   * 创建者仍可见自己的自定义食物。
   */
  async reviewFoodCandidate(candidateId: string, dto: ReviewFoodCandidateDto) {
    const candidate = await this.driver.findFoodCandidateById(candidateId);
    if (!candidate) throw err.notFound();
    if (candidate.status !== 'pending') {
      throw err.conflict({ status: candidate.status });
    }

    if (dto.action === 'reject') {
      await this.driver.updateFoodCandidateStatus(candidateId, 'rejected', dto.reason);
      return this.candidateView(await this.mustGetCandidate(candidateId));
    }

    // 食物已被删除等异常态 → 404（此时不动候选状态，审核可重试）
    if (!(await this.driver.findCustomFoodById(candidate.foodId))) throw err.notFound();
    // 原子晋升：id 不变转共享（既有 FoodEntry 引用不断链），再落候选终态
    await this.driver.promoteCustomFoodToShared(candidate.foodId);
    await this.driver.updateFoodCandidateStatus(candidateId, 'approved');
    return this.candidateView(await this.mustGetCandidate(candidateId));
  }

  /** 状态落库后回读（驱动侧 version+1 / updatedAt 已生效），不存在视为内部异常 */
  private async mustGetCandidate(id: string): Promise<FoodCandidateEntity> {
    const candidate = await this.driver.findFoodCandidateById(id);
    if (!candidate) throw err.notFound();
    return candidate;
  }

  /** 审核前候选食物在个人库，晋升后在共享库（id 不变）；两处都查不到 = 食物已删 */
  private async candidateView(c: FoodCandidateEntity) {
    const food =
      (await this.driver.findCustomFoodById(c.foodId)) ??
      (await this.driver.findFoodById(c.foodId));
    return {
      id: c.id,
      foodId: c.foodId,
      userId: c.userId,
      status: c.status,
      reason: c.reason,
      nameZh: food?.nameZh ?? null,
      nameEn: food?.nameEn ?? null,
      // 管理端审核台展示用（每 100g 营养）；食物已被删除等异常态为 null
      per100g: food
        ? {
            kcal: food.kcalPer100g,
            proteinG: food.proteinPer100g,
            carbG: food.carbsPer100g,
            fatG: food.fatPer100g,
          }
        : null,
      createdAt: c.createdAt.toISOString(),
      updatedAt: c.updatedAt.toISOString(),
    };
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

  private async saveIdempotency(
    userId: string,
    endpoint: string,
    clientRequestId: string,
    payloadHashValue: string,
    responseBody: unknown,
  ) {
    await this.driver.saveIdempotencyRecord({
      userId,
      clientRequestId,
      endpoint,
      payloadHash: payloadHashValue,
      responseBody,
      createdAt: new Date(),
    });
  }
}
