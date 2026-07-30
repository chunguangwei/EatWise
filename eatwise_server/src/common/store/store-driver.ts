import {
  DataStore,
  FastingPlanEntity,
  FastingRecordEntity,
  FoodEntity,
  FoodEntryEntity,
  PostEntity,
  StreakEntity,
  UserEntity,
  WaterLogEntity,
} from './data-store';

/**
 * 仓储驱动抽象（持久化收口）：业务侧通过本接口读写「必须由真实库保证」的操作，
 * 由环境变量 STORE_DRIVER=memory|prisma 选择实现（默认 memory，见 InfraModule）。
 *
 * 现状说明（阶段性迁移）：fasting/streak/social/sync 等业务 Service 仍直接读写
 * 同步内存 DataStore（接口契约不变）；PrismaStore 已覆盖批量上行、导出聚合、
 * 删除清除与食物库种子四条真实持久化路径，供 prisma 模式与后续迁移使用。
 */

/** DI token：STORE_DRIVER 环境变量选择 MemoryStoreDriver / PrismaStore */
export const STORE_DRIVER = 'STORE_DRIVER';

/** U3 导出聚合包（合规 §4.2 查阅复制权：该用户全量个人数据，JSON） */
export interface UserDataExport {
  generatedAt: string; // UTC ISO
  profile: UserEntity;
  foodEntries: FoodEntryEntity[];
  fastingPlans: FastingPlanEntity[];
  fastingRecords: FastingRecordEntity[];
  streak: StreakEntity | null;
  posts: PostEntity[];
  /** 饮水记录（M3 功能点 4；prisma 模式暂无该表，可选字段） */
  waterLogs?: WaterLogEntity[];
}

/** U5 到期删除执行报告（合规 §4.3：个人数据物理删除 + UGC 匿名化） */
export interface PurgeReport {
  userId: string;
  foodEntries: number;
  fastingRecords: number;
  fastingPlans: number;
  postsAnonymized: number;
  refreshTokens: number;
}

/** 食物库种子行（对齐 prisma Food 模型 / foods.seed.json 清洗结果） */
export type FoodSeedRow = Omit<FoodEntity, 'id'> & { id: string };

/** sync/push 批量上行操作（≤100/批，契约 §3.8 / DTO ArrayMaxSize(100)） */
export interface PushEntryOp {
  clientRequestId: string;
  op: 'create' | 'update' | 'delete';
  serverId?: string;
  baseVersion?: number;
  payload?: {
    eatenAt?: string;
    foodId?: string;
    grams?: number;
    inputMethod?: string;
    photoUrl?: string;
  };
}

export interface PushEntryResult {
  clientRequestId: string;
  status: 'applied' | 'conflict' | 'error';
  conflictType?: 'version_mismatch' | 'deleted_vs_modified';
  serverEntry?: FoodEntryEntity | { id: string; deletedAt: Date; version: number };
  errorCode?: string;
}

export abstract class StoreDriver {
  abstract readonly name: 'memory' | 'prisma';

  /** U3：聚合该用户全量数据；用户不存在/已删除返回 null */
  abstract collectUserExport(userId: string): Promise<UserDataExport | null>;

  /** U5 到期执行：物理删除个人数据 + 匿名化打卡帖，单事务 */
  abstract purgeUserData(userId: string): Promise<PurgeReport>;

  /** 到期删除扫描：冷静期满（scheduledDeletionAt <= now）的 pending 用户 id 列表 */
  abstract listDueDeletionUserIds(now: Date): Promise<string[]>;

  /** D-16 食物库全量种子：按 id upsert，幂等可重跑 */
  abstract upsertFoods(rows: FoodSeedRow[]): Promise<number>;
}

/** 内存驱动：适配既有 DataStore（默认模式，行为与历史一致） */
export class MemoryStoreDriver extends StoreDriver {
  readonly name = 'memory' as const;

  constructor(private readonly store: DataStore) {
    super();
  }

  collectUserExport(userId: string): Promise<UserDataExport | null> {
    const user = this.store.users.get(userId);
    if (!user || user.deletedAt) return Promise.resolve(null);
    const foodEntries = [...this.store.foodEntries.values()].filter(
      (e) => e.userId === userId && !e.deletedAt,
    );
    const fastingPlans = [...this.store.fastingPlans.values()].filter((p) => p.userId === userId);
    const fastingRecords = [...this.store.fastingRecords.values()].filter(
      (r) => r.userId === userId,
    );
    const streak = this.store.streaks.get(userId) ?? null;
    const posts = [...this.store.posts.values()].filter((p) => p.userId === userId && !p.deletedAt);
    const waterLogs = [...this.store.waterLogs.values()].filter(
      (e) => e.userId === userId && !e.deletedAt,
    );
    return Promise.resolve({
      generatedAt: new Date().toISOString(),
      profile: user,
      foodEntries,
      fastingPlans,
      fastingRecords,
      streak,
      posts,
      waterLogs,
    });
  }

  purgeUserData(userId: string): Promise<PurgeReport> {
    let foodEntries = 0;
    for (const [id, e] of this.store.foodEntries) {
      if (e.userId === userId) {
        this.store.foodEntries.delete(id);
        foodEntries += 1;
      }
    }
    for (const [id, e] of this.store.waterLogs) {
      if (e.userId === userId) this.store.waterLogs.delete(id);
    }
    let fastingRecords = 0;
    for (const [id, r] of this.store.fastingRecords) {
      if (r.userId === userId) {
        this.store.fastingRecords.delete(id);
        fastingRecords += 1;
      }
    }
    let fastingPlans = 0;
    for (const [id, p] of this.store.fastingPlans) {
      if (p.userId === userId) {
        this.store.fastingPlans.delete(id);
        fastingPlans += 1;
      }
    }
    // UGC 匿名化（合规 §4.3：内容留存口径〔待法务确认〕，〔假设〕清空正文/图片并打 tombstone）
    let postsAnonymized = 0;
    for (const post of this.store.posts.values()) {
      if (post.userId === userId && !post.deletedAt) {
        post.text = '';
        post.imageUrls = [];
        post.deletedAt = new Date();
        post.version += 1;
        postsAnonymized += 1;
      }
    }
    // 点赞/举报幂等键清除
    for (const key of [...this.store.postLikes]) {
      if (key.endsWith(`|${userId}`)) this.store.postLikes.delete(key);
    }
    for (const key of [...this.store.postReports.keys()]) {
      if (key.endsWith(`|${userId}`)) this.store.postReports.delete(key);
    }
    this.store.streaks.delete(userId);
    let refreshTokens = 0;
    for (const [hash, t] of this.store.refreshTokens) {
      if (t.userId === userId) {
        this.store.refreshTokens.delete(hash);
        refreshTokens += 1;
      }
    }
    for (const [key, rec] of this.store.idempotency) {
      if (rec.userId === userId) this.store.idempotency.delete(key);
    }
    const user = this.store.users.get(userId);
    if (user?.phone) this.store.smsCodes.delete(user.phone);
    this.store.users.delete(userId); // 物理删除（合规 §4.3）
    return Promise.resolve({
      userId,
      foodEntries,
      fastingRecords,
      fastingPlans,
      postsAnonymized,
      refreshTokens,
    });
  }

  listDueDeletionUserIds(now: Date): Promise<string[]> {
    const ids = [...this.store.users.values()]
      .filter(
        (u) =>
          u.deletionStatus === 'pending' && u.scheduledDeletionAt && u.scheduledDeletionAt <= now,
      )
      .map((u) => u.id);
    return Promise.resolve(ids);
  }

  upsertFoods(rows: FoodSeedRow[]): Promise<number> {
    for (const row of rows) this.store.foods.set(row.id, { ...row });
    return Promise.resolve(rows.length);
  }
}
