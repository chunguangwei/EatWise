import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../infra/prisma.service';
import { BusinessException, err } from '../errors/business.exception';
import { newId } from '../utils/id.util';
import {
  FastingPlanEntity,
  FastingRecordEntity,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodEntryEntity,
  NutritionSnapshot,
  PostEntity,
  StreakEntity,
  UserEntity,
  WaterLogEntity,
} from './data-store';
import {
  FoodSeedRow,
  PurgeReport,
  PushEntryOp,
  PushEntryResult,
  StoreDriver,
  UserDataExport,
} from './store-driver';

const PUSH_BATCH_MAX = 100; // 单批 ≤100 条（契约 §3.8 〔假设〕，DTO 层同限）
const SEED_CHUNK = 200;

type Tx = Prisma.TransactionClient;

/**
 * Prisma 仓储驱动（STORE_DRIVER=prisma）：真实 PostgreSQL 持久化。
 * - 批量上行：单 $transaction 原子提交；幂等查重靠 (userId, clientRequestId) 唯一约束，
 *   重放返回首次结果、同键不同体报 IDEMPOTENCY_PAYLOAD_MISMATCH（D-20 语义与内存模式一致）；
 * - LWW：update/delete 以 baseVersion 乐观并发（updateMany where version），
 *   updatedAt 由数据库时钟赋值（@updatedAt），客户端时间戳不采信；
 * - U3 导出 / U5 清除：聚合查询（含饮水记录）与单事务物理删除 + UGC 匿名化；
 * - 饮水记录 / 食物候选审核 / 帖子举报计数：真实表读写，唯一约束冲突按幂等重放处理。
 */
@Injectable()
export class PrismaStore extends StoreDriver {
  readonly name = 'prisma' as const;
  private readonly logger = new Logger('PrismaStore');

  constructor(private readonly prisma: PrismaService) {
    super();
  }

  // ===== U3 导出聚合（合规 §4.2）=====
  async collectUserExport(userId: string): Promise<UserDataExport | null> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || user.deletedAt) return null;
    const [foodEntries, fastingPlans, fastingRecords, streak, posts, waterLogs] =
      await Promise.all([
        this.prisma.foodEntry.findMany({ where: { userId, deletedAt: null } }),
        this.prisma.fastingPlan.findMany({ where: { userId } }),
        this.prisma.fastingRecord.findMany({ where: { userId } }),
        this.prisma.streak.findUnique({ where: { userId } }),
        this.prisma.post.findMany({ where: { userId, deletedAt: null } }),
        this.prisma.waterLog.findMany({ where: { userId, deletedAt: null } }),
      ]);
    return {
      generatedAt: new Date().toISOString(),
      profile: toUserEntity(user),
      foodEntries: foodEntries.map(toFoodEntryEntity),
      fastingPlans: fastingPlans.map(toFastingPlanEntity),
      fastingRecords: fastingRecords.map(toFastingRecordEntity),
      streak: streak ? toStreakEntity(streak) : null,
      posts: posts.map(toPostEntity),
      waterLogs: waterLogs.map(toWaterLogEntity),
    };
  }

  // ===== U5 到期执行（合规 §4.3：物理删除个人数据 + UGC 匿名化，单事务）=====
  async purgeUserData(userId: string): Promise<PurgeReport> {
    return this.prisma.$transaction(async (tx) => {
      // UGC 匿名化（内容留存口径〔待法务确认〕：清空正文/图片 + 解除用户关联 + tombstone；
      // posts.userId 可空，物理删用户行不再违反 FK）
      const posts = await tx.post.updateMany({
        where: { userId, deletedAt: null },
        data: {
          text: '',
          imageUrls: [],
          userId: null,
          deletedAt: new Date(),
          version: { increment: 1 },
        },
      });
      const foodEntries = await tx.foodEntry.deleteMany({ where: { userId } });
      const fastingRecords = await tx.fastingRecord.deleteMany({ where: { userId } });
      const fastingPlans = await tx.fastingPlan.deleteMany({ where: { userId } });
      await tx.dailyNutrition.deleteMany({ where: { userId } });
      await tx.waterLog.deleteMany({ where: { userId } }); // users 外键必填，须先于用户行删除
      await tx.streak.deleteMany({ where: { userId } });
      await tx.idempotencyKey.deleteMany({ where: { userId } });
      const tokens = await tx.refreshToken.deleteMany({ where: { userId } });
      await tx.user.deleteMany({ where: { id: userId } }); // 物理删除（幂等：不存在不报错）
      return {
        userId,
        foodEntries: foodEntries.count,
        fastingRecords: fastingRecords.count,
        fastingPlans: fastingPlans.count,
        postsAnonymized: posts.count,
        refreshTokens: tokens.count,
      };
    });
  }

  // ===== 到期删除扫描 =====
  async listDueDeletionUserIds(now: Date): Promise<string[]> {
    const due = await this.prisma.user.findMany({
      where: { deletionStatus: 'pending', scheduledDeletionAt: { lte: now } },
      select: { id: true },
    });
    return due.map((u) => u.id);
  }

  // ===== D-16 食物库种子：分块事务 upsert，幂等可重跑 =====
  async upsertFoods(rows: FoodSeedRow[]): Promise<number> {
    let done = 0;
    for (let i = 0; i < rows.length; i += SEED_CHUNK) {
      const chunk = rows.slice(i, i + SEED_CHUNK);
      await this.prisma.$transaction(
        chunk.map((f) => {
          const data = {
            nameZh: f.nameZh,
            nameEn: f.nameEn,
            aliases: f.aliases,
            kcalPer100g: f.kcalPer100g,
            proteinPer100g: f.proteinPer100g,
            carbsPer100g: f.carbsPer100g,
            fatPer100g: f.fatPer100g,
            category: f.category,
            source: f.source,
          };
          return this.prisma.food.upsert({
            where: { id: f.id },
            create: { id: f.id, ...data },
            update: data,
          });
        }),
      );
      done += chunk.length;
    }
    return done;
  }

  // ===== sync/push 批量上行：单事务原子 + 幂等查重 + 逐条 LWW =====
  async pushFoodEntries(userId: string, ops: PushEntryOp[]): Promise<PushEntryResult[]> {
    if (ops.length > PUSH_BATCH_MAX) {
      throw err.validation({ ops: `batch size ${ops.length} exceeds ${PUSH_BATCH_MAX}` });
    }
    return this.prisma.$transaction(async (tx) => {
      const results: PushEntryResult[] = [];
      for (const op of ops) {
        try {
          results.push(await this.applyOp(tx, userId, op));
        } catch (e) {
          this.logger.warn(`push op ${op.clientRequestId} failed: ${(e as Error).message}`);
          results.push({
            clientRequestId: op.clientRequestId,
            status: 'error',
            errorCode: 'INTERNAL_ERROR',
          });
        }
      }
      return results;
    });
  }

  private async applyOp(tx: Tx, userId: string, op: PushEntryOp): Promise<PushEntryResult> {
    switch (op.op) {
      case 'create':
        return this.applyCreate(tx, userId, op);
      case 'update':
        return this.applyUpdate(tx, userId, op);
      case 'delete':
        return this.applyDelete(tx, userId, op);
      default:
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          errorCode: 'VALIDATION_ERROR',
        };
    }
  }

  private async applyCreate(tx: Tx, userId: string, op: PushEntryOp): Promise<PushEntryResult> {
    const p = op.payload;
    if (!p?.foodId || p.grams == null || !p.eatenAt) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        errorCode: 'VALIDATION_ERROR',
      };
    }
    // 幂等查重：(userId, clientRequestId) 唯一约束；重放返回首次结果
    const dup = await tx.foodEntry.findUnique({
      where: { userId_clientRequestId: { userId, clientRequestId: op.clientRequestId } },
    });
    if (dup) {
      const same =
        dup.foodId === p.foodId &&
        dup.grams === p.grams &&
        dup.eatenAt.toISOString() === new Date(p.eatenAt).toISOString();
      if (!same) {
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          errorCode: 'IDEMPOTENCY_PAYLOAD_MISMATCH',
        };
      }
      return {
        clientRequestId: op.clientRequestId,
        status: 'applied',
        serverEntry: toFoodEntryEntity(dup),
      };
    }
    const snapshot = await this.snapshotOf(tx, p.foodId, p.grams);
    const entry = await tx.foodEntry.create({
      data: {
        id: newId(),
        userId,
        clientRequestId: op.clientRequestId,
        eatenAt: new Date(p.eatenAt),
        foodId: p.foodId,
        grams: p.grams,
        inputMethod: p.inputMethod ?? 'manual',
        photoUrl: p.photoUrl ?? null,
        nutritionSnapshot: snapshot as unknown as Prisma.InputJsonValue,
      },
    });
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: toFoodEntryEntity(entry),
    };
  }

  private async applyUpdate(tx: Tx, userId: string, op: PushEntryOp): Promise<PushEntryResult> {
    const entryId = op.serverId;
    if (!entryId) {
      return { clientRequestId: op.clientRequestId, status: 'error', errorCode: 'NOT_FOUND' };
    }
    const entry = await tx.foodEntry.findUnique({ where: { id: entryId } });
    if (!entry || entry.userId !== userId) {
      return { clientRequestId: op.clientRequestId, status: 'error', errorCode: 'NOT_FOUND' };
    }
    if (entry.deletedAt) {
      // 删除 vs 修改不可合并：双份保留待用户处理（D-20）
      return {
        clientRequestId: op.clientRequestId,
        status: 'conflict',
        conflictType: 'deleted_vs_modified',
        serverEntry: { id: entry.id, deletedAt: entry.deletedAt, version: entry.version },
      };
    }
    // LWW 版本检测：baseVersion 不符 → 返回服务端现值由客户端字段级合并后重试
    if (op.baseVersion == null || op.baseVersion !== entry.version) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'conflict',
        conflictType: 'version_mismatch',
        serverEntry: toFoodEntryEntity(entry),
      };
    }
    const p = op.payload ?? {};
    const foodId = p.foodId ?? entry.foodId;
    const grams = p.grams ?? entry.grams;
    const snapshot = p.foodId || p.grams != null ? await this.snapshotOf(tx, foodId, grams) : null;
    // 乐观并发：where version 保证并发下仅一方成功（另一方方面已先读到现值走 conflict）
    const updated = await tx.foodEntry.updateMany({
      where: { id: entry.id, version: entry.version },
      data: {
        eatenAt: p.eatenAt ? new Date(p.eatenAt) : entry.eatenAt,
        foodId,
        grams,
        inputMethod: p.inputMethod ?? entry.inputMethod,
        ...(snapshot ? { nutritionSnapshot: snapshot as unknown as Prisma.InputJsonValue } : {}),
        version: { increment: 1 },
      },
    });
    if (updated.count === 0) {
      const current = await tx.foodEntry.findUnique({ where: { id: entry.id } });
      return {
        clientRequestId: op.clientRequestId,
        status: 'conflict',
        conflictType: 'version_mismatch',
        serverEntry: current ? toFoodEntryEntity(current) : undefined,
      };
    }
    const fresh = await tx.foodEntry.findUnique({ where: { id: entry.id } });
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: fresh ? toFoodEntryEntity(fresh) : undefined,
    };
  }

  private async applyDelete(tx: Tx, userId: string, op: PushEntryOp): Promise<PushEntryResult> {
    const entryId = op.serverId;
    if (!entryId) {
      return { clientRequestId: op.clientRequestId, status: 'error', errorCode: 'NOT_FOUND' };
    }
    const entry = await tx.foodEntry.findUnique({ where: { id: entryId } });
    if (!entry || entry.userId !== userId) {
      return { clientRequestId: op.clientRequestId, status: 'error', errorCode: 'NOT_FOUND' };
    }
    if (!entry.deletedAt) {
      if (op.baseVersion != null && op.baseVersion !== entry.version) {
        return {
          clientRequestId: op.clientRequestId,
          status: 'conflict',
          conflictType: 'version_mismatch',
          serverEntry: toFoodEntryEntity(entry),
        };
      }
      await tx.foodEntry.update({
        where: { id: entry.id },
        data: { deletedAt: new Date(), version: { increment: 1 } }, // 软删 tombstone
      });
    }
    // 软删幂等：重复删除返回 applied
    return { clientRequestId: op.clientRequestId, status: 'applied' };
  }

  /** 营养快照：按食物库每 100g 值 × grams/100 换算（防食物库更新回溯改历史） */
  private async snapshotOf(tx: Tx, foodId: string, grams: number): Promise<NutritionSnapshot> {
    const food = await tx.food.findUnique({ where: { id: foodId } });
    if (!food) throw err.validation({ foodId: 'unknown food' });
    const f = grams / 100;
    const r = (n: number) => Math.round(n * 10) / 10; // 与内存模式 round1 同口径
    return {
      kcal: r(food.kcalPer100g * f),
      proteinG: r(food.proteinPer100g * f),
      carbsG: r(food.carbsPer100g * f),
      fatG: r(food.fatPer100g * f),
    };
  }

  // ===== 饮水记录（water_logs：create 幂等 + delete tombstone，无 update）=====

  /** 逐条落库；(userId, clientRequestId) 唯一约束冲突视为幂等重放 → 静默成功（D-20） */
  async createWaterLog(log: WaterLogEntity): Promise<void> {
    try {
      await this.prisma.waterLog.create({
        data: {
          id: log.id,
          userId: log.userId,
          clientRequestId: log.clientRequestId,
          amountMl: log.amountMl,
          loggedAt: log.loggedAt,
          localDate: log.localDate,
          version: log.version,
          deletedAt: log.deletedAt,
        },
      });
    } catch (e) {
      if (isUniqueConflict(e)) return; // 重放：首次结果已落库，不覆盖
      throw this.fail('createWaterLog', e);
    }
  }

  /** 软删 tombstone；未命中/重复删除幂等静默（与内存模式同口径） */
  async deleteWaterLog(userId: string, clientRequestId: string): Promise<void> {
    try {
      await this.prisma.waterLog.updateMany({
        where: { userId, clientRequestId, deletedAt: null },
        data: { deletedAt: new Date(), version: { increment: 1 } },
      });
    } catch (e) {
      throw this.fail('deleteWaterLog', e);
    }
  }

  async findWaterLogsByUserAndDate(userId: string, localDate: string): Promise<WaterLogEntity[]> {
    try {
      const rows = await this.prisma.waterLog.findMany({
        where: { userId, localDate, deletedAt: null },
        orderBy: [{ loggedAt: 'asc' }, { id: 'asc' }],
      });
      return rows.map(toWaterLogEntity);
    } catch (e) {
      throw this.fail('findWaterLogsByUserAndDate', e);
    }
  }

  /** syncToken 增量下游标：updatedAt > since（含 tombstone），按 (updatedAt, id) 稳定升序 */
  async findWaterLogsSince(userId: string, since: Date): Promise<WaterLogEntity[]> {
    try {
      const rows = await this.prisma.waterLog.findMany({
        where: { userId, updatedAt: { gt: since } },
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });
      return rows.map(toWaterLogEntity);
    } catch (e) {
      throw this.fail('findWaterLogsSince', e);
    }
  }

  // ===== 共享食物候选（food_candidates，D-17 先审后发）=====

  /** 提交候选；(userId, clientRequestId) 已存在 → 静默（幂等重放由调用方取回首次候选）。
   * 表暂无该唯一索引，故查重后插入（同请求内并发窗口极小）；P2002 兜底同 waterLog。 */
  async createFoodCandidate(candidate: FoodCandidateEntity): Promise<void> {
    try {
      const dup = await this.prisma.foodCandidate.findFirst({
        where: { userId: candidate.userId, clientRequestId: candidate.clientRequestId },
        select: { id: true },
      });
      if (dup) return;
      await this.prisma.foodCandidate.create({
        data: {
          id: candidate.id,
          foodId: candidate.foodId,
          userId: candidate.userId,
          status: candidate.status,
          reason: candidate.reason,
          clientRequestId: candidate.clientRequestId,
          version: candidate.version,
        },
      });
    } catch (e) {
      if (isUniqueConflict(e)) return;
      throw this.fail('createFoodCandidate', e);
    }
  }

  async findFoodCandidateByUserAndRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodCandidateEntity | null> {
    try {
      const row = await this.prisma.foodCandidate.findFirst({
        where: { userId, clientRequestId },
        orderBy: { createdAt: 'asc' }, // 先入为准
      });
      return row ? toFoodCandidateEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodCandidateByUserAndRequestId', e);
    }
  }

  /** 审核落库（pending → approved/rejected，version+1）；候选不存在抛 NOT_FOUND */
  async updateFoodCandidateStatus(
    id: string,
    status: FoodCandidateStatus,
    reason?: string,
  ): Promise<void> {
    const trimmed = reason === undefined ? undefined : (reason.trim() || null);
    try {
      const updated = await this.prisma.foodCandidate.updateMany({
        where: { id },
        data: {
          status,
          ...(trimmed === undefined ? {} : { reason: trimmed }),
          version: { increment: 1 },
        },
      });
      if (updated.count === 0) throw err.notFound();
    } catch (e) {
      throw this.fail('updateFoodCandidateStatus', e);
    }
  }

  // ===== 社区举报计数（M5：reported 队列按 reportCount / reportedAt 排序）=====

  async incrementPostReportCount(postId: string): Promise<void> {
    try {
      const updated = await this.prisma.post.updateMany({
        where: { id: postId },
        data: { reportCount: { increment: 1 }, reportedAt: new Date() },
      });
      if (updated.count === 0) throw err.notFound();
    } catch (e) {
      throw this.fail('incrementPostReportCount', e);
    }
  }

  /** 驱动层异常 → 业务异常（Prisma 错误类型不外泄给 Service；已是业务异常则原样抛） */
  private fail(op: string, e: unknown): never {
    if (e instanceof BusinessException) throw e;
    this.logger.error(`${op} failed: ${(e as Error).message}`);
    throw err.internal();
  }
}

// ===== Prisma row → 实体映射（Json 字段按内存实体类型收窄）=====

function toUserEntity(u: Prisma.UserGetPayload<object>): UserEntity {
  return {
    id: u.id,
    phone: u.phone,
    username: u.username,
    passwordHash: u.passwordHash,
    nickname: u.nickname,
    gender: u.gender,
    birthYear: u.birthYear,
    heightCm: u.heightCm,
    weightKg: u.weightKg,
    activityLevel: u.activityLevel,
    goal: u.goal,
    locale: u.locale,
    timezone: u.timezone,
    themePref: u.themePref,
    accessibilityPrefs: (u.accessibilityPrefs as Record<string, unknown> | null) ?? null,
    onboardingStatus: u.onboardingStatus,
    deletionStatus: u.deletionStatus,
    scheduledDeletionAt: u.scheduledDeletionAt,
    version: u.version,
    createdAt: u.createdAt,
    updatedAt: u.updatedAt,
    deletedAt: u.deletedAt,
  };
}

function toFoodEntryEntity(e: Prisma.FoodEntryGetPayload<object>): FoodEntryEntity {
  return {
    id: e.id,
    userId: e.userId,
    clientRequestId: e.clientRequestId,
    eatenAt: e.eatenAt,
    foodId: e.foodId,
    grams: e.grams,
    inputMethod: e.inputMethod,
    photoUrl: e.photoUrl,
    nutritionSnapshot: e.nutritionSnapshot as unknown as NutritionSnapshot,
    version: e.version,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    deletedAt: e.deletedAt,
  };
}

function toFastingPlanEntity(p: Prisma.FastingPlanGetPayload<object>): FastingPlanEntity {
  return {
    id: p.id,
    userId: p.userId,
    planType: p.planType,
    eatingWindowStart: p.eatingWindowStart,
    eatingWindowEnd: p.eatingWindowEnd,
    effectiveDate: p.effectiveDate,
    status: p.status as FastingPlanEntity['status'],
    clientRequestId: p.clientRequestId,
    version: p.version,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  };
}

function toFastingRecordEntity(r: Prisma.FastingRecordGetPayload<object>): FastingRecordEntity {
  return {
    id: r.id,
    userId: r.userId,
    attributionDate: r.attributionDate,
    plannedStartAt: r.plannedStartAt,
    plannedEndAt: r.plannedEndAt,
    actualStartAt: r.actualStartAt,
    actualEndAt: r.actualEndAt,
    extendedMinutes: r.extendedMinutes,
    fastedMinutes: r.fastedMinutes,
    result: r.result as FastingRecordEntity['result'],
    isQualified: r.isQualified,
    eventLog: (r.eventLog as FastingRecordEntity['eventLog']) ?? [],
    clientRequestId: r.clientRequestId,
    version: r.version,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

function toStreakEntity(s: Prisma.StreakGetPayload<object>): StreakEntity {
  return {
    id: s.id,
    userId: s.userId,
    currentStreak: s.currentStreak,
    longestStreak: s.longestStreak,
    lastQualifiedDate: s.lastQualifiedDate,
    milestones: (s.milestones as Record<string, string>) ?? {},
    makeupCards: (s.makeupCards as unknown as StreakEntity['makeupCards'] | null) ?? {
      stock: 0,
      month: '',
      usedDates: [],
    },
    version: s.version,
    updatedAt: s.updatedAt,
  };
}

function toPostEntity(p: Prisma.PostGetPayload<object>): PostEntity {
  return {
    id: p.id,
    // U5 匿名化留存的帖子 userId 为 null，实体层以 '' 表示已匿名作者。
    userId: p.userId ?? '',
    clientRequestId: p.clientRequestId,
    text: p.text,
    imageUrls: p.imageUrls,
    streakDaysAtPost: p.streakDaysAtPost,
    likeCount: p.likeCount,
    auditStatus: p.auditStatus as PostEntity['auditStatus'],
    auditReason: (p.auditReason as PostEntity['auditReason']) ?? null,
    reportCount: p.reportCount,
    reportedAt: p.reportedAt,
    visibility: p.visibility,
    version: p.version,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
    deletedAt: p.deletedAt,
  };
}

function toWaterLogEntity(w: Prisma.WaterLogGetPayload<object>): WaterLogEntity {
  return {
    id: w.id,
    userId: w.userId,
    clientRequestId: w.clientRequestId,
    amountMl: w.amountMl,
    loggedAt: w.loggedAt,
    localDate: w.localDate,
    version: w.version,
    createdAt: w.createdAt,
    updatedAt: w.updatedAt,
    deletedAt: w.deletedAt,
  };
}

function toFoodCandidateEntity(c: Prisma.FoodCandidateGetPayload<object>): FoodCandidateEntity {
  return {
    id: c.id,
    foodId: c.foodId,
    userId: c.userId,
    status: c.status as FoodCandidateStatus,
    reason: c.reason,
    clientRequestId: c.clientRequestId,
    version: c.version,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
  };
}

/** P2002 唯一约束冲突：幂等重放的正常结果，不是错误（D-20） */
function isUniqueConflict(e: unknown): boolean {
  return e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002';
}
