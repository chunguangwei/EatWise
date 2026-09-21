import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import {
  CustomFoodEntity,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodCorrectionSuggestion,
  FoodEntity,
} from '../common/store/data-store';
import { FoodSearchHit, STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { clampPageLimit, parseOffsetCursor } from '../common/utils/pagination.util';
import { ContentModerationService } from '../social/moderation/content-moderation.service';
import { BARCODE_PATTERN, BarcodeFoodView } from './barcode/barcode.service';
import {
  ContributeFoodDto,
  CreateCustomFoodDto,
  CreateFoodCorrectionDto,
  ReviewFoodCandidateDto,
  UpdateCustomFoodDto,
} from './food.dto';
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
    limit = clampPageLimit(limit, 20, 50); // 非法 limit（负数/NaN/小数）回落默认，上限 50
    const offset = cursor ? parseOffsetCursor(cursor) : 0;
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
   * 更新自定义食物（个人库编辑，LWW 不做幂等——重放同值无害，D-20 口径外）。
   * 仅创建者可改（他人/共享/已删 → 404，不泄露存在性）；
   * 名称/营养校验与 createCustomFood 同口径（trim 后 1-50 字 / isPer100gInRange）。
   */
  async updateCustomFood(userId: string, foodId: string, dto: UpdateCustomFoodDto) {
    const food = await this.driver.findCustomFoodById(foodId);
    if (!food || food.userId !== userId) throw err.notFound();

    const nameZh = dto.nameZh.trim();
    if (nameZh.length < 1 || nameZh.length > 50) {
      throw err.validation({ nameZh: 'trimmed length must be 1-50' });
    }
    if (!isPer100gInRange(dto.per100g)) {
      throw err.validation({ per100g: 'out of range (kcal 0-900, macros 0-100)' });
    }

    await this.driver.updateCustomFood(foodId, {
      nameZh,
      nameEn: dto.nameEn?.trim() || nameZh, // 〔假设〕未给英文名时回退中文名（同 create）
      aliases: [...(dto.aliasesZh ?? []), ...(dto.aliasesEn ?? [])]
        .map((a) => a.trim())
        .filter(Boolean),
      kcalPer100g: dto.per100g.kcal,
      proteinPer100g: dto.per100g.proteinG,
      carbsPer100g: dto.per100g.carbG,
      fatPer100g: dto.per100g.fatG,
      source: dto.source,
    });
    const updated = await this.driver.findCustomFoodById(foodId);
    if (!updated) throw err.notFound();
    return this.customView(updated);
  }

  /**
   * 删除自定义食物（软删 tombstone；prisma deletedAt / 内存移行，读路径即时隐藏）。
   * 仅创建者可删（他人/共享/已删 → 404，不泄露存在性）；
   * 已有 pending 共享候选（审核中）→ 409 FOOD_UNDER_REVIEW：审核结论要回写该食物
   * （approve 晋升 / reject 联动清记录），删除须先撤销或等审核落定。
   * rejected 候选不阻断（candidateView 已容忍食物缺失回退 null，审核台不悬空）。
   * 级联：本人引用该食物的饮食记录全部 tombstone（sync/pull 下行，其它设备自动清）。
   * 不做幂等：重删第二次 404（资源已不存在的自然语义）。
   */
  async deleteCustomFood(userId: string, foodId: string) {
    const food = await this.driver.findCustomFoodById(foodId);
    if (!food || food.userId !== userId) throw err.notFound();

    const candidate = await this.driver.findFoodCandidateByFoodId(foodId);
    if (candidate?.status === 'pending') throw err.foodUnderReview();

    await this.driver.softDeleteCustomFood(foodId);
    const deletedEntries = await this.driver.softDeleteFoodEntriesByFood(userId, foodId);
    return { deleted: true, deletedEntries };
  }

  /**
   * 贡献自定义食物为共享候选（食物库扩充第三层，先审后发 D-17）。
   * - 只能贡献自己的自定义食物（他人的/不存在的 → 404，不泄露存在性）；
   * - 幂等：clientRequestId 重放返回首次结果（不同体 409）；同一食物已有候选时直接返回原状态；
   * - 条码商品补录（OFF 未命中）：barcode + evidenceImageUrl 成对出现即 kind=barcode；
   *   同 barcode 查重口径：pending → 幂等返回已有候选；approved → 409 已上架；
   *   rejected 不阻断（修正照片/营养后可重新提交）；
   * - 食物名过机审：rejected → 拒收 FOOD_CONTRIBUTE_REJECTED；manual → 仍入池，状态 pending 转人工。
   */
  async contributeCustomFood(userId: string, foodId: string, dto: ContributeFoodDto) {
    const endpoint = 'foods/custom/contribute';
    const barcode = dto.barcode?.trim() || null;
    const evidenceImageUrl = dto.evidenceImageUrl?.trim() || null;
    // 条码与佐证照片成对出现：条码贡献必须带营养表照片（「对答案」根基），单传照片无意义同样拒
    if (barcode && !BARCODE_PATTERN.test(barcode)) {
      throw err.validation({ barcode: 'barcode must be 8-14 digits' });
    }
    if (barcode && !evidenceImageUrl) {
      throw err.validation({ evidenceImageUrl: 'required when barcode is present' });
    }
    if (!barcode && evidenceImageUrl) {
      throw err.validation({ barcode: 'required when evidenceImageUrl is present' });
    }
    const hash = payloadHash({ foodId, barcode, evidenceImageUrl });
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const food = await this.driver.findCustomFoodById(foodId);
    if (!food || food.userId !== userId) throw err.notFound();

    // 同一食物只允许一个候选：pending/approved 重复贡献幂等返回原状态；
    // rejected 视为重新提交——重置回 pending（清驳回理由/审核留痕）回到人工审核池。
    // 机审不再重跑：名称首次提交已过机审，池内 rejected 是人工终审结论，重提交通道
    // 本就该由终审再裁（改名走 PATCH 后重提交同样成立，池内可见最新行）。
    const existing = await this.driver.findFoodCandidateByFoodId(foodId);
    if (existing) {
      if (existing.status === 'rejected') {
        await this.driver.updateFoodCandidateStatus(existing.id, 'pending', '', null);
      }
      const response = await this.candidateView(await this.mustGetCandidate(existing.id));
      await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
      return response;
    }

    // 条码查重（同 barcode 的阻断性候选：pending/approved；rejected 已被驱动过滤）
    if (barcode) {
      const dup = await this.driver.findFoodCandidateByBarcode(barcode);
      if (dup?.status === 'approved') {
        throw err.conflict({ barcode, status: 'approved' }); // 已上架共享库，无需重复贡献
      }
      if (dup) {
        const response = await this.candidateView(dup);
        await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
        return response;
      }
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
      kind: barcode ? 'barcode' : 'custom',
      barcode,
      evidenceImageUrl,
      suggestion: null,
      reviewedBy: null,
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

  /**
   * 已有共享食物的数据纠错（食物详情页「数据有误？」入口，与贡献同池审核）：
   * - 目标必须是共享库食物（自定义食物不存在于共享库 → 404，不泄露存在性）；
   * - 幂等：clientRequestId 重放返回首次结果（不同体 409）；
   * - 同人同食物已有 pending 纠错 → 直接返回该候选（重复提交不堆队列；改值需等审核落定）；
   * - 建议中文名过机审：rejected → 拒收 FOOD_CONTRIBUTE_REJECTED；
   * - 候选 kind=correction，建议值存 suggestion；approve 后应用到共享食物行。
   */
  async createFoodCorrection(userId: string, foodId: string, dto: CreateFoodCorrectionDto) {
    const endpoint = 'foods/correction';
    const nameZh = dto.nameZh?.trim() || null;
    const nameEn = dto.nameEn?.trim() || null;
    if (nameZh && nameZh.length > 50) {
      throw err.validation({ nameZh: 'trimmed length must be 1-50' });
    }
    if (!isPer100gInRange(dto.per100g)) {
      throw err.validation({ per100g: 'out of range (kcal 0-900, macros 0-100)' });
    }
    const hash = payloadHash({ foodId, nameZh, nameEn, per100g: dto.per100g });
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const food = await this.driver.findFoodById(foodId);
    if (!food) throw err.notFound();

    // 同人同食物已有 pending 纠错：幂等返回原候选（不同建议值不覆盖，避免审核目标漂移）
    const mine = await this.driver.findFoodCandidatesByUser(userId, 'pending');
    const dup = mine.find((c) => c.kind === 'correction' && c.foodId === foodId);
    if (dup) {
      const response = await this.candidateView(dup);
      await this.saveIdempotency(userId, endpoint, dto.clientRequestId, hash, response);
      return response;
    }

    if (nameZh) {
      const verdict = await this.moderation.moderate(nameZh, []);
      if (verdict.verdict === 'rejected') {
        throw err.foodContributeRejected(verdict.reason);
      }
    }

    const suggestion: FoodCorrectionSuggestion = {
      nameZh: nameZh && nameZh !== food.nameZh ? nameZh : null,
      nameEn: nameEn && nameEn !== food.nameEn ? nameEn : null,
      per100g: {
        kcal: dto.per100g.kcal,
        proteinG: dto.per100g.proteinG,
        carbG: dto.per100g.carbG,
        fatG: dto.per100g.fatG,
      },
    };
    const now = new Date();
    const candidate: FoodCandidateEntity = {
      id: `fc_${newId().slice(0, 8)}`,
      foodId,
      userId,
      status: 'pending',
      reason: null,
      kind: 'correction',
      barcode: null,
      evidenceImageUrl: null,
      suggestion,
      reviewedBy: null,
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

  /**
   * 条码查询第一跳：自有共享库（条码众包上架商品，foods.barcode）精确命中 →
   * 与 OFF 命中同构的视图，source='eatwise' 区分来源。未命中返回 null，由调用方
   * 回落 OFF 代理。自有库命中不走 BarcodeService（不触发外呼、不进 OFF 缓存），
   * 因此后来上架的自有商品不会被先前 OFF 缓存命中遮蔽。
   */
  async lookupOwnBarcode(rawCode: string): Promise<BarcodeFoodView | null> {
    const code = rawCode.trim();
    if (!BARCODE_PATTERN.test(code)) return null; // 格式非法交给 OFF 路径统一报 VALIDATION_ERROR
    const food = await this.driver.findFoodByBarcode(code);
    if (!food) return null;
    return {
      id: food.id,
      barcode: code,
      nameZh: food.nameZh,
      nameEn: food.nameEn,
      aliases: food.aliases,
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbsPer100g: food.carbsPer100g,
      fatPer100g: food.fatPer100g,
      source: 'eatwise',
      isCustom: false,
    };
  }

  /** 管理端：审核队列（游标分页，createdAt 升序先入先审；status 过滤） */
  async listFoodCandidates(status: FoodCandidateStatus | undefined, limit = 20, cursor?: string) {
    limit = clampPageLimit(limit, 20, 50);
    const offset = cursor ? parseOffsetCursor(cursor) : 0;
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
        kind: c.kind,
        barcode: c.barcode,
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
   * reject 幂等：已 rejected 重复驳回直接返回当前状态（不报错、reason 不覆写）；
   * 首次驳回（kind != correction）级联软删贡献者引用该食物的饮食记录——配合客户端
   * 乐观入账（未入库食品先记），驳回后 sync/pull 下行 tombstone 清除相关记录，
   * 客户端再按「我的贡献」状态迁移补本地清理与提示。kind=correction 不动记录
   * （目标食物仍在共享库，驳回仅表示建议值不采纳）。
   * kind=correction（数据纠错）approve → 建议值应用到共享食物行（建议名非空才改名，
   * 每 100g 四营养整体覆写），id 与既有 FoodEntry 引用不变（条目营养为入账快照，不回溯）。
   * [reviewedBy] 审核留痕：管理端为管理员账号 id（x-admin-token 兜底为 null），
   * 移动端审批中心为用户 id。
   */
  async reviewFoodCandidate(
    candidateId: string,
    dto: ReviewFoodCandidateDto,
    reviewedBy?: string | null,
  ) {
    const candidate = await this.driver.findFoodCandidateById(candidateId);
    if (!candidate) throw err.notFound();

    if (dto.action === 'reject') {
      // 幂等驳回：重复驳回返回当前状态（首次 reason 不覆写）
      if (candidate.status === 'rejected') return this.candidateView(candidate);
      if (candidate.status !== 'pending') {
        throw err.conflict({ status: candidate.status });
      }
      await this.driver.updateFoodCandidateStatus(candidateId, 'rejected', dto.reason, reviewedBy);
      if (candidate.kind !== 'correction') {
        // 乐观入账联动：清除贡献者引用该食物的记录（软删，随 sync/pull 下行）
        await this.driver.softDeleteFoodEntriesByFood(candidate.userId, candidate.foodId);
      }
      return this.candidateView(await this.mustGetCandidate(candidateId));
    }

    if (candidate.status !== 'pending') {
      throw err.conflict({ status: candidate.status });
    }

    if (candidate.kind === 'correction') {
      // 数据纠错：目标共享行存在且建议值完整才应用；异常态 → 404（不动候选状态，审核可重试）
      if (!candidate.suggestion || !(await this.driver.findFoodById(candidate.foodId))) {
        throw err.notFound();
      }
      await this.driver.applyFoodCorrection(candidate.foodId, candidate.suggestion);
      await this.driver.updateFoodCandidateStatus(candidateId, 'approved', undefined, reviewedBy);
      return this.candidateView(await this.mustGetCandidate(candidateId));
    }

    // 食物已被删除等异常态 → 404（此时不动候选状态，审核可重试）
    if (!(await this.driver.findCustomFoodById(candidate.foodId))) throw err.notFound();
    // 原子晋升：id 不变转共享（既有 FoodEntry 引用不断链）；条码候选把 barcode 写入共享行，
    // 后续扫码优先命中自有库。再落候选终态
    await this.driver.promoteCustomFoodToShared(
      candidate.foodId,
      candidate.kind === 'barcode' ? candidate.barcode : null,
    );
    await this.driver.updateFoodCandidateStatus(candidateId, 'approved', undefined, reviewedBy);
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
      kind: c.kind,
      barcode: c.barcode,
      evidenceImageUrl: c.evidenceImageUrl,
      // kind=correction：建议值（审核台与 per100g 原值对照展示）；其余类型为 null
      suggestion: c.suggestion,
      // 审核留痕（终审执行者；未审核为 null）
      reviewedBy: c.reviewedBy,
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
