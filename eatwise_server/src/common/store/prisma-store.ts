import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../infra/prisma.service';
import { BusinessException, err } from '../errors/business.exception';
import { newId } from '../utils/id.util';
import {
  AdminUserEntity,
  CustomFoodEntity,
  FastingPlanEntity,
  FastingRecordEntity,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodEntity,
  FoodEntryEntity,
  IdempotencyRecord,
  ModerationQueueItem,
  NutritionSnapshot,
  PostEntity,
  RefreshTokenEntity,
  StreakEntity,
  UserEntity,
  WaterLogEntity,
} from './data-store';
import {
  FoodSearchHit,
  FoodSeedRow,
  PostAdminFilter,
  PurgeReport,
  PushEntryOp,
  PushEntryResult,
  StoreDriver,
  UserDataExport,
  UserProfilePatch,
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
 * - 全量 CRUD 基座：用户/会话令牌/断食/食物/饮食记录/Streak/幂等/帖子/点赞举报/
 *   审核队列/管理员账号全实体覆盖（StoreDriver 抽象，见 store-driver.ts）。
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
      await tx.postLike.deleteMany({ where: { userId } }); // 点赞/举报幂等记录随账号清除（内存模式同口径）
      await tx.postReport.deleteMany({ where: { userId } });
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

  // ===== 用户 =====

  async findUserById(userId: string): Promise<UserEntity | null> {
    try {
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      return user ? toUserEntity(user) : null;
    } catch (e) {
      throw this.fail('findUserById', e);
    }
  }

  async findUserByPhone(phone: string): Promise<UserEntity | null> {
    try {
      const user = await this.prisma.user.findFirst({ where: { phone, deletedAt: null } });
      return user ? toUserEntity(user) : null;
    } catch (e) {
      throw this.fail('findUserByPhone', e);
    }
  }

  async findUserByUsername(username: string): Promise<UserEntity | null> {
    try {
      // 小写归一化匹配（含软删用户：username 唯一占位语义）
      const user = await this.prisma.user.findFirst({
        where: { username: { equals: username.trim().toLowerCase(), mode: 'insensitive' } },
      });
      return user ? toUserEntity(user) : null;
    } catch (e) {
      throw this.fail('findUserByUsername', e);
    }
  }

  async createUser(partial: Partial<UserEntity>): Promise<UserEntity> {
    const now = new Date();
    try {
      const user = await this.prisma.user.create({
        data: {
          id: partial.id ?? newId(),
          phone: partial.phone ?? null,
          username: partial.username ?? null,
          passwordHash: partial.passwordHash ?? null,
          nickname: partial.nickname ?? null,
          gender: partial.gender ?? null,
          birthYear: partial.birthYear ?? null,
          heightCm: partial.heightCm ?? null,
          weightKg: partial.weightKg ?? null,
          activityLevel: partial.activityLevel ?? null,
          goal: partial.goal ?? null,
          locale: partial.locale ?? 'zh-CN',
          timezone: partial.timezone ?? 'Asia/Shanghai',
          themePref: partial.themePref ?? 'system',
          accessibilityPrefs: (partial.accessibilityPrefs ??
            Prisma.DbNull) as Prisma.InputJsonValue,
          onboardingStatus: partial.onboardingStatus ?? 'none',
          deletionStatus: partial.deletionStatus ?? null,
          scheduledDeletionAt: partial.scheduledDeletionAt ?? null,
          createdAt: partial.createdAt ?? now,
          updatedAt: partial.updatedAt ?? now,
          deletedAt: partial.deletedAt ?? null,
        },
      });
      return toUserEntity(user);
    } catch (e) {
      throw this.fail('createUser', e);
    }
  }

  /** U2 资料 LWW：仅更新给定字段，version+1、updatedAt=服务端时钟；不存在/已删 → NOT_FOUND */
  async updateUserProfile(userId: string, patch: UserProfilePatch): Promise<UserEntity> {
    const data: Prisma.UserUpdateInput = {};
    for (const [key, value] of Object.entries(patch)) {
      if (value !== undefined) (data as Record<string, unknown>)[key] = value;
    }
    try {
      const updated = await this.prisma.user.updateMany({
        where: { id: userId, deletedAt: null },
        data: { ...data, version: { increment: 1 }, updatedAt: new Date() },
      });
      if (updated.count === 0) throw err.notFound();
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      return toUserEntity(user!);
    } catch (e) {
      throw this.fail('updateUserProfile', e);
    }
  }

  async updateUserDeletion(
    userId: string,
    deletionStatus: string | null,
    scheduledDeletionAt: Date | null,
  ): Promise<UserEntity> {
    try {
      const updated = await this.prisma.user.updateMany({
        where: { id: userId, deletedAt: null },
        data: { deletionStatus, scheduledDeletionAt, version: { increment: 1 }, updatedAt: new Date() },
      });
      if (updated.count === 0) throw err.notFound();
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      return toUserEntity(user!);
    } catch (e) {
      throw this.fail('updateUserDeletion', e);
    }
  }

  /** 修改密码落库（changePassword）：直存新哈希，version+1；不存在/已删 → NOT_FOUND */
  async updateUserPasswordHash(userId: string, passwordHash: string): Promise<UserEntity> {
    try {
      const updated = await this.prisma.user.updateMany({
        where: { id: userId, deletedAt: null },
        data: { passwordHash, version: { increment: 1 }, updatedAt: new Date() },
      });
      if (updated.count === 0) throw err.notFound();
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      return toUserEntity(user!);
    } catch (e) {
      throw this.fail('updateUserPasswordHash', e);
    }
  }

  // ===== 会话令牌（refresh_tokens）=====

  async createRefreshToken(token: RefreshTokenEntity): Promise<void> {
    try {
      await this.prisma.refreshToken.create({ data: { ...token } });
    } catch (e) {
      throw this.fail('createRefreshToken', e);
    }
  }

  async findRefreshTokenByHash(tokenHash: string): Promise<RefreshTokenEntity | null> {
    try {
      const row = await this.prisma.refreshToken.findUnique({ where: { tokenHash } });
      return row ? toRefreshTokenEntity(row) : null;
    } catch (e) {
      throw this.fail('findRefreshTokenByHash', e);
    }
  }

  async listActiveRefreshTokens(userId: string): Promise<RefreshTokenEntity[]> {
    try {
      const rows = await this.prisma.refreshToken.findMany({
        where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
        orderBy: { createdAt: 'asc' },
      });
      return rows.map(toRefreshTokenEntity);
    } catch (e) {
      throw this.fail('listActiveRefreshTokens', e);
    }
  }

  /** refresh 滑动轮换：置 revokedAt + replacedBy；重复调用幂等静默 */
  async rotateRefreshToken(tokenHash: string, replacedBy: string): Promise<void> {
    try {
      await this.prisma.refreshToken.updateMany({
        where: { tokenHash },
        data: { revokedAt: new Date(), replacedBy },
      });
    } catch (e) {
      throw this.fail('rotateRefreshToken', e);
    }
  }

  async revokeRefreshToken(tokenHash: string): Promise<void> {
    try {
      await this.prisma.refreshToken.updateMany({
        where: { tokenHash, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    } catch (e) {
      throw this.fail('revokeRefreshToken', e);
    }
  }

  async revokeUserRefreshTokens(userId: string, deviceId?: string): Promise<number> {
    try {
      const updated = await this.prisma.refreshToken.updateMany({
        where: { userId, revokedAt: null, ...(deviceId ? { deviceId } : {}) },
        data: { revokedAt: new Date() },
      });
      return updated.count;
    } catch (e) {
      throw this.fail('revokeUserRefreshTokens', e);
    }
  }

  // ===== 断食方案 =====

  async listFastingPlansByUser(userId: string): Promise<FastingPlanEntity[]> {
    try {
      const rows = await this.prisma.fastingPlan.findMany({ where: { userId } });
      return rows.map(toFastingPlanEntity);
    } catch (e) {
      throw this.fail('listFastingPlansByUser', e);
    }
  }

  async saveFastingPlan(plan: FastingPlanEntity): Promise<void> {
    try {
      await this.prisma.fastingPlan.upsert({
        where: { id: plan.id },
        create: { ...plan },
        update: { ...plan },
      });
    } catch (e) {
      throw this.fail('saveFastingPlan', e);
    }
  }

  // ===== 断食记录 =====

  async findFastingRecordById(id: string): Promise<FastingRecordEntity | null> {
    try {
      const row = await this.prisma.fastingRecord.findUnique({ where: { id } });
      return row ? toFastingRecordEntity(row) : null;
    } catch (e) {
      throw this.fail('findFastingRecordById', e);
    }
  }

  async findFastingRecordByPlannedEnd(
    userId: string,
    plannedEndAt: Date,
  ): Promise<FastingRecordEntity | null> {
    try {
      const row = await this.prisma.fastingRecord.findFirst({
        where: { userId, plannedEndAt },
      });
      return row ? toFastingRecordEntity(row) : null;
    } catch (e) {
      throw this.fail('findFastingRecordByPlannedEnd', e);
    }
  }

  async listFastingRecordsByUser(userId: string): Promise<FastingRecordEntity[]> {
    try {
      const rows = await this.prisma.fastingRecord.findMany({ where: { userId } });
      return rows.map(toFastingRecordEntity);
    } catch (e) {
      throw this.fail('listFastingRecordsByUser', e);
    }
  }

  async saveFastingRecord(record: FastingRecordEntity): Promise<void> {
    const data = {
      ...record,
      eventLog: record.eventLog as unknown as Prisma.InputJsonValue,
    };
    try {
      await this.prisma.fastingRecord.upsert({
        where: { id: record.id },
        create: data,
        update: data,
      });
    } catch (e) {
      throw this.fail('saveFastingRecord', e);
    }
  }

  // ===== 食物库 =====

  async findFoodById(id: string): Promise<FoodEntity | null> {
    try {
      // 仅内置/共享库（自定义食物行 isCustom=true，走 findCustomFoodById）
      const row = await this.prisma.food.findFirst({ where: { id, isCustom: false } });
      return row ? toFoodEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodById', e);
    }
  }

  async createCustomFood(food: CustomFoodEntity): Promise<void> {
    try {
      await this.prisma.food.create({
        data: {
          id: food.id,
          nameZh: food.nameZh,
          nameEn: food.nameEn,
          aliases: food.aliases,
          kcalPer100g: food.kcalPer100g,
          proteinPer100g: food.proteinPer100g,
          carbsPer100g: food.carbsPer100g,
          fatPer100g: food.fatPer100g,
          category: '自定义',
          source: food.source,
          isCustom: true,
          createdByUserId: food.userId,
          clientRequestId: food.clientRequestId,
          createdAt: food.createdAt,
        },
      });
    } catch (e) {
      throw this.fail('createCustomFood', e);
    }
  }

  async findCustomFoodById(id: string): Promise<CustomFoodEntity | null> {
    try {
      const row = await this.prisma.food.findFirst({ where: { id, isCustom: true } });
      return row ? toCustomFoodEntity(row) : null;
    } catch (e) {
      throw this.fail('findCustomFoodById', e);
    }
  }

  async findCustomFoodsByUser(userId: string): Promise<CustomFoodEntity[]> {
    try {
      const rows = await this.prisma.food.findMany({
        where: { createdByUserId: userId, isCustom: true },
      });
      return rows.map(toCustomFoodEntity);
    } catch (e) {
      throw this.fail('findCustomFoodsByUser', e);
    }
  }
  /**
   * K1 搜索：可见性（内置共享 || 本人自定义）在 SQL 层过滤；打分/排序与
   * food.service matchAll 同口径（nameZh 原文包含 / nameEn、aliases 大小写不敏感；
   * 前缀 3 > 子串 2 > 别名 1，组内同分 nameZh 升序，自定义整体置后）。
   */
  async searchFoods(
    q: string,
    userId?: string,
    _locale?: string,
    limit?: number,
  ): Promise<FoodSearchHit[]> {
    const raw = q.trim();
    const ql = raw.toLowerCase();
    if (!ql) return [];
    try {
      // SQL 层只做可见性过滤（内置/共享 + 本人自定义）；命中判定在 JS 侧完成——
      // aliases 为字符串数组，Prisma 标量列表无子串匹配能力，且 nameZh 需与内存
      // includes 同口径（区分大小写），统一交给 toSearchHit 一份逻辑（同内存全表扫描）。
      const rows = await this.prisma.food.findMany({
        where: {
          OR: [
            { isCustom: false },
            ...(userId ? [{ isCustom: true, createdByUserId: userId }] : []),
          ],
        },
      });
      const matched = rows
        .map((row) => toSearchHit(row, raw, ql))
        .filter((h): h is FoodSearchHit => h !== null);
      const byScore = (a: FoodSearchHit, b: FoodSearchHit) =>
        b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh);
      const all = [
        ...matched.filter((h) => !h.isCustom).sort(byScore),
        ...matched.filter((h) => h.isCustom).sort(byScore),
      ];
      return limit != null ? all.slice(0, limit) : all;
    } catch (e) {
      throw this.fail('searchFoods', e);
    }
  }

  /**
   * 审核晋升（原子）：自定义行就地转共享（id 不变，FoodEntry 引用不断链）。
   * 非自定义/不存在 → NOT_FOUND（与内存 promoteCustomFoodToShared 同口径）。
   */
  async promoteCustomFoodToShared(foodId: string): Promise<void> {
    try {
      const updated = await this.prisma.food.updateMany({
        where: { id: foodId, isCustom: true },
        data: { isCustom: false, source: 'community', category: '社区共享' },
      });
      if (updated.count === 0) throw err.notFound();
    } catch (e) {
      throw this.fail('promoteCustomFoodToShared', e);
    }
  }

  // ===== 食物候选审核（读路径）=====

  async findFoodCandidateById(id: string): Promise<FoodCandidateEntity | null> {
    try {
      const row = await this.prisma.foodCandidate.findUnique({ where: { id } });
      return row ? toFoodCandidateEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodCandidateById', e);
    }
  }

  async listFoodCandidates(status?: FoodCandidateStatus): Promise<FoodCandidateEntity[]> {
    try {
      const rows = await this.prisma.foodCandidate.findMany({
        where: status ? { status } : {},
        orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], // 先入先审
      });
      return rows.map(toFoodCandidateEntity);
    } catch (e) {
      throw this.fail('listFoodCandidates', e);
    }
  }

  async findFoodCandidateByFoodId(foodId: string): Promise<FoodCandidateEntity | null> {
    try {
      const row = await this.prisma.foodCandidate.findFirst({
        where: { foodId },
        orderBy: { createdAt: 'asc' },
      });
      return row ? toFoodCandidateEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodCandidateByFoodId', e);
    }
  }

  async findFoodCandidatesByUser(
    userId: string,
    status?: FoodCandidateStatus,
  ): Promise<FoodCandidateEntity[]> {
    try {
      const rows = await this.prisma.foodCandidate.findMany({
        where: { userId, ...(status ? { status } : {}) },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], // 我的贡献：最新在前
      });
      return rows.map(toFoodCandidateEntity);
    } catch (e) {
      throw this.fail('findFoodCandidatesByUser', e);
    }
  }

  async deleteCustomFood(id: string): Promise<void> {
    try {
      await this.prisma.food.deleteMany({ where: { id, isCustom: true } });
    } catch (e) {
      throw this.fail('deleteCustomFood', e);
    }
  }

  // ===== 饮食记录 =====

  async findFoodEntryById(id: string): Promise<FoodEntryEntity | null> {
    try {
      const row = await this.prisma.foodEntry.findUnique({ where: { id } });
      return row ? toFoodEntryEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodEntryById', e);
    }
  }

  async findFoodEntryByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodEntryEntity | null> {
    try {
      const row = await this.prisma.foodEntry.findUnique({
        where: { userId_clientRequestId: { userId, clientRequestId } },
      });
      return row ? toFoodEntryEntity(row) : null;
    } catch (e) {
      throw this.fail('findFoodEntryByClientRequestId', e);
    }
  }

  async listFoodEntriesByUser(userId: string): Promise<FoodEntryEntity[]> {
    try {
      const rows = await this.prisma.foodEntry.findMany({
        where: { userId },
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });
      return rows.map(toFoodEntryEntity);
    } catch (e) {
      throw this.fail('listFoodEntriesByUser', e);
    }
  }

  async saveFoodEntry(entry: FoodEntryEntity): Promise<void> {
    const data = {
      ...entry,
      nutritionSnapshot: entry.nutritionSnapshot as unknown as Prisma.InputJsonValue,
    };
    try {
      await this.prisma.foodEntry.upsert({ where: { id: entry.id }, create: data, update: data });
    } catch (e) {
      throw this.fail('saveFoodEntry', e);
    }
  }

  // ===== Streak =====

  async findStreakByUser(userId: string): Promise<StreakEntity | null> {
    try {
      const row = await this.prisma.streak.findUnique({ where: { userId } });
      return row ? toStreakEntity(row) : null;
    } catch (e) {
      throw this.fail('findStreakByUser', e);
    }
  }

  async saveStreak(streak: StreakEntity): Promise<void> {
    const data = {
      currentStreak: streak.currentStreak,
      longestStreak: streak.longestStreak,
      lastQualifiedDate: streak.lastQualifiedDate,
      milestones: streak.milestones as unknown as Prisma.InputJsonValue,
      makeupCards: streak.makeupCards as unknown as Prisma.InputJsonValue,
      version: streak.version,
      updatedAt: streak.updatedAt,
    };
    try {
      await this.prisma.streak.upsert({
        where: { userId: streak.userId },
        create: { id: streak.id, userId: streak.userId, ...data },
        update: data,
      });
    } catch (e) {
      throw this.fail('saveStreak', e);
    }
  }

  // ===== 幂等表 =====

  async findIdempotencyRecord(
    userId: string,
    endpoint: string,
    clientRequestId: string,
  ): Promise<IdempotencyRecord | null> {
    try {
      const row = await this.prisma.idempotencyKey.findUnique({
        where: { userId_clientRequestId_endpoint: { userId, clientRequestId, endpoint } },
      });
      return row ? toIdempotencyRecord(row) : null;
    } catch (e) {
      throw this.fail('findIdempotencyRecord', e);
    }
  }

  async saveIdempotencyRecord(record: IdempotencyRecord): Promise<void> {
    const data = {
      userId: record.userId,
      clientRequestId: record.clientRequestId,
      endpoint: record.endpoint,
      payloadHash: record.payloadHash,
      responseBody: record.responseBody as Prisma.InputJsonValue,
      createdAt: record.createdAt,
    };
    try {
      await this.prisma.idempotencyKey.upsert({
        where: {
          userId_clientRequestId_endpoint: {
            userId: record.userId,
            clientRequestId: record.clientRequestId,
            endpoint: record.endpoint,
          },
        },
        create: data,
        update: {
          payloadHash: data.payloadHash,
          responseBody: data.responseBody,
          createdAt: data.createdAt,
        },
      });
    } catch (e) {
      throw this.fail('saveIdempotencyRecord', e);
    }
  }

  // ===== 打卡帖 =====

  async findPostById(id: string): Promise<PostEntity | null> {
    try {
      const row = await this.prisma.post.findUnique({ where: { id } });
      return row ? toPostEntity(row) : null;
    } catch (e) {
      throw this.fail('findPostById', e);
    }
  }

  async savePost(post: PostEntity): Promise<void> {
    const data = {
      userId: post.userId || null, // 实体 '' 表示已匿名作者（U5），落库为 null
      clientRequestId: post.clientRequestId,
      text: post.text,
      imageUrls: post.imageUrls,
      streakDaysAtPost: post.streakDaysAtPost,
      likeCount: post.likeCount,
      auditStatus: post.auditStatus,
      auditReason: (post.auditReason ?? Prisma.DbNull) as Prisma.InputJsonValue,
      reportCount: post.reportCount,
      reportedAt: post.reportedAt,
      visibility: post.visibility,
      version: post.version,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
      deletedAt: post.deletedAt,
    };
    try {
      await this.prisma.post.upsert({ where: { id: post.id }, create: { id: post.id, ...data }, update: data });
    } catch (e) {
      throw this.fail('savePost', e);
    }
  }

  async findFeedPosts(viewerId: string): Promise<PostEntity[]> {
    try {
      const rows = await this.prisma.post.findMany({
        where: {
          deletedAt: null,
          OR: [{ auditStatus: 'approved' }, { userId: viewerId }],
        },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      });
      return rows.map(toPostEntity);
    } catch (e) {
      throw this.fail('findFeedPosts', e);
    }
  }

  async listPostsForAdmin(filter: PostAdminFilter | undefined): Promise<PostEntity[]> {
    const where: Prisma.PostWhereInput = { deletedAt: null };
    if (filter === 'pending' || filter === 'approved') where.auditStatus = filter;
    else if (filter === 'rejected') {
      where.auditStatus = 'rejected';
      where.reportCount = 0;
    } else if (filter === 'reported') {
      where.auditStatus = 'rejected';
      where.reportCount = { gt: 0 };
    }
    try {
      const rows = await this.prisma.post.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      });
      return rows.map(toPostEntity);
    } catch (e) {
      throw this.fail('listPostsForAdmin', e);
    }
  }

  /** 点赞：post_likes 插入 + likeCount/version 自增，单事务；(postId,userId) 冲突 = 幂等静默 */
  async likePost(postId: string, userId: string): Promise<void> {
    try {
      await this.prisma.$transaction(async (tx) => {
        const post = await tx.post.findUnique({ where: { id: postId }, select: { id: true } });
        if (!post) throw err.notFound();
        try {
          await tx.postLike.create({ data: { id: newId(), postId, userId } });
        } catch (e) {
          if (isUniqueConflict(e)) return; // 已点赞：幂等静默
          throw e;
        }
        await tx.post.update({
          where: { id: postId },
          data: { likeCount: { increment: 1 }, version: { increment: 1 }, updatedAt: new Date() },
        });
      });
    } catch (e) {
      throw this.fail('likePost', e);
    }
  }

  async unlikePost(postId: string, userId: string): Promise<void> {
    try {
      await this.prisma.$transaction(async (tx) => {
        const post = await tx.post.findUnique({ where: { id: postId }, select: { id: true } });
        if (!post) throw err.notFound();
        const removed = await tx.postLike.deleteMany({ where: { postId, userId } });
        if (removed.count > 0) {
          // likeCount 下限 0（内存模式 Math.max(0, count-1) 同口径）
          await tx.post.updateMany({
            where: { id: postId, likeCount: { gt: 0 } },
            data: { likeCount: { decrement: 1 }, version: { increment: 1 }, updatedAt: new Date() },
          });
        }
      });
    } catch (e) {
      throw this.fail('unlikePost', e);
    }
  }

  async hasPostLike(postId: string, userId: string): Promise<boolean> {
    try {
      const row = await this.prisma.postLike.findFirst({
        where: { postId, userId },
        select: { id: true },
      });
      return row !== null;
    } catch (e) {
      throw this.fail('hasPostLike', e);
    }
  }

  async hasPostReport(postId: string, userId: string): Promise<boolean> {
    try {
      const row = await this.prisma.postReport.findFirst({
        where: { postId, userId },
        select: { id: true },
      });
      return row !== null;
    } catch (e) {
      throw this.fail('hasPostReport', e);
    }
  }

  async createPostReport(
    postId: string,
    userId: string,
    reason?: string | null,
  ): Promise<void> {
    try {
      await this.prisma.postReport.create({
        data: { id: newId(), postId, userId, reason: reason ?? null },
      });
    } catch (e) {
      if (isUniqueConflict(e)) return; // 同用户同帖重复举报：幂等静默
      throw this.fail('createPostReport', e);
    }
  }

  // ===== 人工审核队列 =====

  async enqueueModerationItem(item: ModerationQueueItem): Promise<void> {
    try {
      await this.prisma.moderationQueue.create({
        data: {
          postId: item.postId,
          source: item.source,
          reason: item.reason,
          createdAt: item.createdAt,
        },
      });
    } catch (e) {
      throw this.fail('enqueueModerationItem', e);
    }
  }

  async listModerationQueue(): Promise<ModerationQueueItem[]> {
    try {
      const rows = await this.prisma.moderationQueue.findMany({ orderBy: { seq: 'asc' } });
      return rows.map(toModerationQueueItem);
    } catch (e) {
      throw this.fail('listModerationQueue', e);
    }
  }

  async removeModerationByPost(postId: string): Promise<number> {
    try {
      const removed = await this.prisma.moderationQueue.deleteMany({ where: { postId } });
      return removed.count;
    } catch (e) {
      throw this.fail('removeModerationByPost', e);
    }
  }

  // ===== 管理员账号 =====

  async countAdminUsers(): Promise<number> {
    try {
      return await this.prisma.adminUser.count();
    } catch (e) {
      throw this.fail('countAdminUsers', e);
    }
  }

  async findAdminByUsername(username: string): Promise<AdminUserEntity | null> {
    try {
      const row = await this.prisma.adminUser.findFirst({
        where: { username: { equals: username.trim().toLowerCase(), mode: 'insensitive' } },
      });
      return row ? toAdminUserEntity(row) : null;
    } catch (e) {
      throw this.fail('findAdminByUsername', e);
    }
  }

  async findAdminById(id: string): Promise<AdminUserEntity | null> {
    try {
      const row = await this.prisma.adminUser.findUnique({ where: { id } });
      return row ? toAdminUserEntity(row) : null;
    } catch (e) {
      throw this.fail('findAdminById', e);
    }
  }

  async createAdminUser(
    partial: Omit<AdminUserEntity, 'id' | 'createdAt'>,
  ): Promise<AdminUserEntity> {
    try {
      const row = await this.prisma.adminUser.create({
        data: { id: newId(), ...partial, createdAt: new Date() },
      });
      return toAdminUserEntity(row);
    } catch (e) {
      throw this.fail('createAdminUser', e);
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

function toFoodEntity(f: Prisma.FoodGetPayload<object>): FoodEntity {
  return {
    id: f.id,
    nameZh: f.nameZh,
    nameEn: f.nameEn,
    aliases: f.aliases,
    kcalPer100g: f.kcalPer100g,
    proteinPer100g: f.proteinPer100g,
    carbsPer100g: f.carbsPer100g,
    fatPer100g: f.fatPer100g,
    category: f.category ?? '',
    source: f.source ?? '',
    createdByUserId: f.createdByUserId,
  };
}

function toCustomFoodEntity(f: Prisma.FoodGetPayload<object>): CustomFoodEntity {
  return {
    id: f.id,
    userId: f.createdByUserId ?? '',
    clientRequestId: f.clientRequestId ?? '',
    nameZh: f.nameZh,
    nameEn: f.nameEn,
    aliases: f.aliases,
    kcalPer100g: f.kcalPer100g,
    proteinPer100g: f.proteinPer100g,
    carbsPer100g: f.carbsPer100g,
    fatPer100g: f.fatPer100g,
    source: (f.source as CustomFoodEntity['source']) ?? 'manual',
    createdAt: f.createdAt,
  };
}

function toRefreshTokenEntity(t: Prisma.RefreshTokenGetPayload<object>): RefreshTokenEntity {
  return {
    id: t.id,
    userId: t.userId,
    tokenHash: t.tokenHash,
    deviceId: t.deviceId,
    expiresAt: t.expiresAt,
    revokedAt: t.revokedAt,
    replacedBy: t.replacedBy,
    createdAt: t.createdAt,
  };
}

function toAdminUserEntity(a: Prisma.AdminUserGetPayload<object>): AdminUserEntity {
  return {
    id: a.id,
    username: a.username,
    passwordHash: a.passwordHash,
    role: a.role as AdminUserEntity['role'],
    disabled: a.disabled,
    createdAt: a.createdAt,
  };
}

function toIdempotencyRecord(r: Prisma.IdempotencyKeyGetPayload<object>): IdempotencyRecord {
  return {
    userId: r.userId,
    clientRequestId: r.clientRequestId,
    endpoint: r.endpoint,
    payloadHash: r.payloadHash,
    responseBody: r.responseBody,
    createdAt: r.createdAt,
  };
}

function toModerationQueueItem(q: Prisma.ModerationQueueGetPayload<object>): ModerationQueueItem {
  return {
    postId: q.postId,
    source: q.source as ModerationQueueItem['source'],
    reason: q.reason,
    createdAt: q.createdAt,
  };
}

/** K1 命中打分（与 food.service.matchFood 同口径）：前缀 3 > 子串 2 > 别名 1 */
function toSearchHit(
  f: Prisma.FoodGetPayload<object>,
  q: string,
  ql: string,
): FoodSearchHit | null {
  const food: FoodEntity = {
    id: f.id,
    nameZh: f.nameZh,
    nameEn: f.nameEn,
    aliases: f.aliases,
    kcalPer100g: f.kcalPer100g,
    proteinPer100g: f.proteinPer100g,
    carbsPer100g: f.carbsPer100g,
    fatPer100g: f.fatPer100g,
    category: f.category ?? '',
    source: f.source ?? '',
    createdByUserId: f.createdByUserId,
  };
  const isCustom = f.isCustom;
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

/** P2002 唯一约束冲突：幂等重放的正常结果，不是错误（D-20） */
function isUniqueConflict(e: unknown): boolean {
  return e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002';
}
