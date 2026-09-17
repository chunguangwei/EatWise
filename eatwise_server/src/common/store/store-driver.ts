import { err } from '../errors/business.exception';
import {
  AdminUserEntity,
  CustomFoodEntity,
  DataStore,
  FastingPlanEntity,
  FastingRecordEntity,
  FoodCandidateEntity,
  FoodCandidateStatus,
  FoodEntity,
  FoodEntryEntity,
  IdempotencyRecord,
  ModerationQueueItem,
  PostEntity,
  RefreshTokenEntity,
  StreakEntity,
  UserEntity,
  WaterLogEntity,
} from './data-store';

/**
 * 仓储驱动抽象（持久化收口，2026-09-08 完成）：业务 Service 全部经本接口读写，
 * 由环境变量 STORE_DRIVER=memory|prisma 选择实现（默认 memory，见 InfraModule）。
 * MemoryStoreDriver 适配同步内存 DataStore（行为与历史一致）；PrismaStore 覆盖
 * 全实体真实落库（用户/令牌/断食/饮食/饮水/streak/帖子/点赞举报/审核队列/
 * 自定义食物/幂等键），仅 smsCodes（mock）与管理端登录限流保留内存。
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
  /** 饮水记录（M3 功能点 4）：真实库 water_logs 表全量 */
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

  // ===== 饮水记录（PRD M3 功能点 4：轻量两态，仅 create/软删，无 update）=====

  /** 逐条落库；(userId, clientRequestId) 已存在视为幂等重放，静默成功（D-20） */
  abstract createWaterLog(log: WaterLogEntity): Promise<void>;

  /** 软删 tombstone（deletedAt + version+1）；重复删除幂等静默 */
  abstract deleteWaterLog(userId: string, clientRequestId: string): Promise<void>;

  /** 当日饮水明细（按 loggedAt 升序；排除 tombstone） */
  abstract findWaterLogsByUserAndDate(userId: string, localDate: string): Promise<WaterLogEntity[]>;

  /** syncToken 增量下游标：updatedAt > since（含 tombstone），按 (updatedAt, id) 升序 */
  abstract findWaterLogsSince(userId: string, since: Date): Promise<WaterLogEntity[]>;

  // ===== 共享食物候选（D-17 先审后发审核池）=====

  /** 提交候选；(userId, clientRequestId) 已存在视为幂等重放，静默成功 */
  abstract createFoodCandidate(candidate: FoodCandidateEntity): Promise<void>;

  /** 按贡献幂等键定位候选（重放返回首次候选） */
  abstract findFoodCandidateByUserAndRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodCandidateEntity | null>;

  /** 审核落库：pending → approved/rejected，version+1；候选不存在抛 NOT_FOUND */
  abstract updateFoodCandidateStatus(
    id: string,
    status: FoodCandidateStatus,
    reason?: string,
  ): Promise<void>;

  // ===== 社区举报计数（M5：举报即下架，reported 队列按 reportCount/reportedAt 排序）=====

  /** reportCount+1 且 reportedAt=now；帖子不存在抛 NOT_FOUND */
  abstract incrementPostReportCount(postId: string): Promise<void>;

  // ===== 用户（U2 资料 LWW / U5 删除状态机；findUserById 原始读取含软删，调用方自判）=====

  abstract findUserById(userId: string): Promise<UserEntity | null>;

  /** 按手机号定位，排除已软删用户 */
  abstract findUserByPhone(phone: string): Promise<UserEntity | null>;

  /** 用户名唯一索引语义：小写归一化匹配，软删用户仍占位（对齐 prisma username @unique） */
  abstract findUserByUsername(username: string): Promise<UserEntity | null>;

  /** 新建用户：缺省值同内存 createUser，id/createdAt 由驱动赋值 */
  abstract createUser(partial: Partial<UserEntity>): Promise<UserEntity>;

  /** U2 资料字段级 LWW：仅更新给定字段，version+1、updatedAt=服务端时钟；不存在/已删 → NOT_FOUND */
  abstract updateUserProfile(userId: string, patch: UserProfilePatch): Promise<UserEntity>;

  /** U5/U6 删除状态机落库（deletionStatus + scheduledDeletionAt），version+1；不存在/已删 → NOT_FOUND */
  abstract updateUserDeletion(
    userId: string,
    deletionStatus: string | null,
    scheduledDeletionAt: Date | null,
  ): Promise<UserEntity>;

  /** 修改密码落库（changePassword）：直存新哈希，version+1、updatedAt=now；不存在/已删 → NOT_FOUND */
  abstract updateUserPasswordHash(userId: string, passwordHash: string): Promise<UserEntity>;

  // ===== 会话令牌（refresh_tokens，主键 tokenHash）=====

  abstract createRefreshToken(token: RefreshTokenEntity): Promise<void>;

  abstract findRefreshTokenByHash(tokenHash: string): Promise<RefreshTokenEntity | null>;

  /** 活跃会话：未吊销且未过期，按 createdAt 升序（多端上限踢最旧依据） */
  abstract listActiveRefreshTokens(userId: string): Promise<RefreshTokenEntity[]>;

  /** refresh 滑动轮换：置 revokedAt=now + replacedBy=新令牌哈希；重复调用幂等静默 */
  abstract rotateRefreshToken(tokenHash: string, replacedBy: string): Promise<void>;

  /** 吊销单条（revokedAt=now）；重复吊销幂等静默 */
  abstract revokeRefreshToken(tokenHash: string): Promise<void>;

  /** 按用户吊销活跃会话（deviceId 缺省 = 全部端），返回吊销条数 */
  abstract revokeUserRefreshTokens(userId: string, deviceId?: string): Promise<number>;

  // ===== 断食方案（fasting_plans；同 userId 仅一条 current 由 Service 保证）=====

  abstract listFastingPlansByUser(userId: string): Promise<FastingPlanEntity[]>;

  /** 按 id upsert（新建 pending / 整体替换 LWW） */
  abstract saveFastingPlan(plan: FastingPlanEntity): Promise<void>;

  // ===== 断食记录（fasting_records）=====

  abstract findFastingRecordById(id: string): Promise<FastingRecordEntity | null>;

  /** 活跃记录定位：userId + 计划结束时刻精确匹配 */
  abstract findFastingRecordByPlannedEnd(
    userId: string,
    plannedEndAt: Date,
  ): Promise<FastingRecordEntity | null>;

  /** 进行中记录定位：result=on_track 的最新一条（按 plannedEndAt 降序）。
   * 延长会后移 plannedEndAt、脱离 plan 窗口精确匹配口径，状态判定须优先按本方法查（F1） */
  abstract findOngoingFastingRecord(userId: string): Promise<FastingRecordEntity | null>;

  abstract listFastingRecordsByUser(userId: string): Promise<FastingRecordEntity[]>;

  /** 按 id upsert（含 eventLog 全量回写；endFast/extend/makeup 状态机落库） */
  abstract saveFastingRecord(record: FastingRecordEntity): Promise<void>;

  // ===== 食物库（内置/共享 + 个人自定义；种子/搜索读取走既有 upsertFoods 与本组方法）=====

  /** 内置/共享食物按 id 读取（自定义食物走 findCustomFoodById） */
  abstract findFoodById(id: string): Promise<FoodEntity | null>;

  /** 共享库按条码精确命中（isCustom=false；条码查询第一跳，命中后不再代理 OFF） */
  abstract findFoodByBarcode(barcode: string): Promise<FoodEntity | null>;

  abstract createCustomFood(food: CustomFoodEntity): Promise<void>;

  abstract findCustomFoodById(id: string): Promise<CustomFoodEntity | null>;

  abstract findCustomFoodsByUser(userId: string): Promise<CustomFoodEntity[]>;

  /**
   * K1 双语食物搜索候选集（内置/共享 isCustom=false + 该用户自定义，与 food.service
   * matchAll 同口径）：q 匹配 nameZh 原文 / nameEn / aliases 大小写不敏感；
   * 内置（含审核晋升共享）排前、自定义排后，组内 score 降序（前缀 3 > 子串 2 > 别名 1）、
   * 同分 nameZh 升序。空/全空白 q 返回 []。locale 仅语言偏好（D-15），不参与过滤。
   */
  abstract searchFoods(
    q: string,
    userId?: string,
    locale?: string,
    limit?: number,
  ): Promise<FoodSearchHit[]>;

  // ===== 食物候选审核（food_candidates；既有 create/findByRequestId/updateStatus 之外的读路径）=====

  abstract findFoodCandidateById(id: string): Promise<FoodCandidateEntity | null>;

  /** 管理端审核队列：status 缺省返回全部，(createdAt 升序, id 升序) 先入先审 */
  abstract listFoodCandidates(status?: FoodCandidateStatus): Promise<FoodCandidateEntity[]>;

  /** 用户端「我的贡献」：仅本人候选，status 缺省全状态，(createdAt 降序, id 降序) 最新在前 */
  abstract findFoodCandidatesByUser(
    userId: string,
    status?: FoodCandidateStatus,
  ): Promise<FoodCandidateEntity[]>;

  /** contribute 幂等定位：同一食物只允许一个候选 */
  abstract findFoodCandidateByFoodId(foodId: string): Promise<FoodCandidateEntity | null>;

  /**
   * 条码贡献查重：返回该条码的阻断性候选（status pending/approved；pending 优先、
   * 其次 approved，同级按 createdAt 升序取最早一条）。rejected 不阻断重提交，返回 null。
   */
  abstract findFoodCandidateByBarcode(barcode: string): Promise<FoodCandidateEntity | null>;

  /**
   * 审核晋升（原子）：自定义食物行转共享——isCustom=false、source='community'、
   * category='社区共享'、保留 id 与 createdByUserId（FoodEntry 引用不断链）；
   * 条码候选（kind=barcode）晋升时把 barcode 一并写入共享行，后续扫码命中自有库。
   * 目标不存在或非自定义行 → NOT_FOUND；候选状态仍由调用方走 updateFoodCandidateStatus。
   */
  abstract promoteCustomFoodToShared(foodId: string, barcode?: string | null): Promise<void>;

  /** 审核晋升/删除时物理移除个人库条目 */
  abstract deleteCustomFood(id: string): Promise<void>;

  // ===== 饮食记录（food_entries；批量上行走 PrismaStore.pushFoodEntries 既有路径）=====

  abstract findFoodEntryById(id: string): Promise<FoodEntryEntity | null>;

  abstract findFoodEntryByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodEntryEntity | null>;

  /** 全量（含 tombstone），按 (updatedAt 升序, id 升序)——sync/pull 增量游标语义 */
  abstract listFoodEntriesByUser(userId: string): Promise<FoodEntryEntity[]>;

  /** 按 id upsert */
  abstract saveFoodEntry(entry: FoodEntryEntity): Promise<void>;

  // ===== Streak（streaks，业务键 userId @unique）=====

  abstract findStreakByUser(userId: string): Promise<StreakEntity | null>;

  /** 按 userId upsert（recompute/rollover 全量落库） */
  abstract saveStreak(streak: StreakEntity): Promise<void>;

  // ===== 幂等表（idempotency_keys，键 userId|endpoint|clientRequestId）=====

  abstract findIdempotencyRecord(
    userId: string,
    endpoint: string,
    clientRequestId: string,
  ): Promise<IdempotencyRecord | null>;

  abstract saveIdempotencyRecord(record: IdempotencyRecord): Promise<void>;

  // ===== 打卡帖（posts；C2 打卡流 / 管理端审核队列）=====

  abstract findPostById(id: string): Promise<PostEntity | null>;

  /** 按 id upsert（发布/删除 tombstone/审核决定等状态机落库） */
  abstract savePost(post: PostEntity): Promise<void>;

  /** 打卡流可见集：未删除 && (approved || 本人)，createdAt 倒序 + id 倒序 */
  abstract findFeedPosts(viewerId: string): Promise<PostEntity[]>;

  /** 管理端审核队列口径：pending / approved / rejected(=rejected 且 reportCount==0) /
   * reported(=rejected 且 reportCount>0) / 全部(缺省)；均未删除，createdAt 倒序 + id 倒序 */
  abstract listPostsForAdmin(filter: PostAdminFilter | undefined): Promise<PostEntity[]>;

  /** 点赞：幂等（postId+userId 唯一），首次 likeCount+1/version+1/updatedAt=now；帖子不存在 → NOT_FOUND */
  abstract likePost(postId: string, userId: string): Promise<void>;

  /** 取消点赞：仅当点赞存在时 likeCount-1（下限 0）/version+1；否则静默；帖子不存在 → NOT_FOUND */
  abstract unlikePost(postId: string, userId: string): Promise<void>;

  abstract hasPostLike(postId: string, userId: string): Promise<boolean>;

  abstract hasPostReport(postId: string, userId: string): Promise<boolean>;

  /** 举报记录落库；(postId, userId) 唯一冲突 = 幂等重放静默 */
  abstract createPostReport(postId: string, userId: string, reason?: string | null): Promise<void>;

  // ===== 人工审核队列（moderation_queue，入队顺序即 seq 升序）=====

  abstract enqueueModerationItem(item: ModerationQueueItem): Promise<void>;

  /** 按入队顺序返回（createdAt/seq 升序） */
  abstract listModerationQueue(): Promise<ModerationQueueItem[]>;

  /** 审核决定后清出该帖全部队列条目，返回删除条数 */
  abstract removeModerationByPost(postId: string): Promise<number>;

  // ===== 管理员账号（admin_users，控制台登录体系）=====

  abstract countAdminUsers(): Promise<number>;

  /** 小写归一化匹配用户名 */
  abstract findAdminByUsername(username: string): Promise<AdminUserEntity | null>;

  abstract findAdminById(id: string): Promise<AdminUserEntity | null>;

  abstract createAdminUser(
    partial: Omit<AdminUserEntity, 'id' | 'createdAt'>,
  ): Promise<AdminUserEntity>;
}

/** U2 可更新资料字段（与 user.service PATCHABLE 对齐） */
export type UserProfilePatch = Partial<
  Pick<
    UserEntity,
    | 'nickname'
    | 'gender'
    | 'birthYear'
    | 'heightCm'
    | 'weightKg'
    | 'activityLevel'
    | 'goal'
    | 'timezone'
    | 'locale'
    | 'themePref'
    | 'accessibilityPrefs'
    | 'onboardingStatus'
  >
>;

/** 管理端帖子队列筛选（与 social.service AdminPostFilter 同口径） */
export type PostAdminFilter = 'pending' | 'approved' | 'rejected' | 'reported';

/** 食物搜索命中（与 food.service FoodSearchHit 同构；驱动返回候选集，分页/视图留在 Service） */
export interface FoodSearchHit {
  food: FoodEntity | CustomFoodEntity;
  isCustom: boolean;
  score: number;
  matchedOn: 'nameZh' | 'nameEn' | 'alias';
  highlight: { field: string; text: string };
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
    // 个人自定义食物与贡献候选随账号清除（审核晋升的共享食物已转出个人库，留存）
    for (const [id, f] of this.store.customFoods) {
      if (f.userId === userId) this.store.customFoods.delete(id);
    }
    for (const [id, c] of this.store.foodCandidates) {
      if (c.userId === userId) this.store.foodCandidates.delete(id);
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

  // ===== 饮水记录（与 sync.service 内存实现同口径：create 幂等 + delete tombstone）=====

  createWaterLog(log: WaterLogEntity): Promise<void> {
    const dup = this.findWaterByClientRequestId(log.userId, log.clientRequestId);
    if (!dup) this.store.waterLogs.set(log.id, log); // 幂等重放：同键已落 → 静默成功
    return Promise.resolve();
  }

  deleteWaterLog(userId: string, clientRequestId: string): Promise<void> {
    const log = this.findWaterByClientRequestId(userId, clientRequestId);
    if (log && !log.deletedAt) {
      log.deletedAt = new Date();
      log.version += 1;
      log.updatedAt = new Date();
    }
    return Promise.resolve(); // 未命中/重复删：幂等静默
  }

  findWaterLogsByUserAndDate(userId: string, localDate: string): Promise<WaterLogEntity[]> {
    const rows = [...this.store.waterLogs.values()]
      .filter((e) => e.userId === userId && e.localDate === localDate && !e.deletedAt)
      .sort((a, b) => a.loggedAt.getTime() - b.loggedAt.getTime() || a.id.localeCompare(b.id));
    return Promise.resolve(rows);
  }

  findWaterLogsSince(userId: string, since: Date): Promise<WaterLogEntity[]> {
    const rows = [...this.store.waterLogs.values()]
      .filter((e) => e.userId === userId && e.updatedAt.getTime() > since.getTime())
      .sort((a, b) => a.updatedAt.getTime() - b.updatedAt.getTime() || a.id.localeCompare(b.id));
    return Promise.resolve(rows);
  }

  // ===== 共享食物候选（与 food.service 内存实现同口径）=====

  createFoodCandidate(candidate: FoodCandidateEntity): Promise<void> {
    const dup = this.findFoodCandidateByUserAndRequestIdSync(
      candidate.userId,
      candidate.clientRequestId,
    );
    if (!dup) this.store.foodCandidates.set(candidate.id, candidate);
    return Promise.resolve();
  }

  findFoodCandidateByUserAndRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodCandidateEntity | null> {
    return Promise.resolve(
      this.findFoodCandidateByUserAndRequestIdSync(userId, clientRequestId) ?? null,
    );
  }

  updateFoodCandidateStatus(
    id: string,
    status: FoodCandidateStatus,
    reason?: string,
  ): Promise<void> {
    const candidate = this.store.foodCandidates.get(id);
    if (!candidate) return Promise.reject(err.notFound());
    candidate.status = status;
    if (status === 'rejected') candidate.reason = reason?.trim() || null;
    else if (reason !== undefined) candidate.reason = reason.trim() || null;
    candidate.version += 1;
    candidate.updatedAt = new Date();
    return Promise.resolve();
  }

  // ===== 社区举报计数 =====

  incrementPostReportCount(postId: string): Promise<void> {
    const post = this.store.posts.get(postId);
    if (!post) return Promise.reject(err.notFound());
    post.reportCount += 1;
    post.reportedAt = new Date();
    return Promise.resolve();
  }

  // ===== 用户 =====

  findUserById(userId: string): Promise<UserEntity | null> {
    return Promise.resolve(this.store.users.get(userId) ?? null);
  }

  findUserByPhone(phone: string): Promise<UserEntity | null> {
    return Promise.resolve(this.store.findUserByPhone(phone) ?? null);
  }

  findUserByUsername(username: string): Promise<UserEntity | null> {
    return Promise.resolve(this.store.findUserByUsername(username) ?? null);
  }

  createUser(partial: Partial<UserEntity>): Promise<UserEntity> {
    return Promise.resolve(this.store.createUser(partial));
  }

  updateUserProfile(userId: string, patch: UserProfilePatch): Promise<UserEntity> {
    const user = this.mustGetUser(userId);
    for (const [key, value] of Object.entries(patch)) {
      if (value !== undefined) {
        (user as unknown as Record<string, unknown>)[key] = value;
      }
    }
    user.version += 1;
    user.updatedAt = new Date(); // 服务端时钟赋值，与内存 patchMe 同口径
    return Promise.resolve(user);
  }

  updateUserDeletion(
    userId: string,
    deletionStatus: string | null,
    scheduledDeletionAt: Date | null,
  ): Promise<UserEntity> {
    const user = this.mustGetUser(userId);
    user.deletionStatus = deletionStatus;
    user.scheduledDeletionAt = scheduledDeletionAt;
    user.version += 1;
    user.updatedAt = new Date();
    return Promise.resolve(user);
  }

  updateUserPasswordHash(userId: string, passwordHash: string): Promise<UserEntity> {
    const user = this.mustGetUser(userId);
    user.passwordHash = passwordHash;
    user.version += 1;
    user.updatedAt = new Date();
    return Promise.resolve(user);
  }

  // ===== 会话令牌 =====

  createRefreshToken(token: RefreshTokenEntity): Promise<void> {
    this.store.refreshTokens.set(token.tokenHash, token);
    return Promise.resolve();
  }

  findRefreshTokenByHash(tokenHash: string): Promise<RefreshTokenEntity | null> {
    return Promise.resolve(this.store.refreshTokens.get(tokenHash) ?? null);
  }

  listActiveRefreshTokens(userId: string): Promise<RefreshTokenEntity[]> {
    const rows = [...this.store.refreshTokens.values()]
      .filter((t) => t.userId === userId && !t.revokedAt && t.expiresAt.getTime() > Date.now())
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
    return Promise.resolve(rows);
  }

  revokeRefreshToken(tokenHash: string): Promise<void> {
    const token = this.store.refreshTokens.get(tokenHash);
    if (token && !token.revokedAt) token.revokedAt = new Date();
    return Promise.resolve();
  }

  rotateRefreshToken(tokenHash: string, replacedBy: string): Promise<void> {
    const token = this.store.refreshTokens.get(tokenHash);
    if (token) {
      token.revokedAt = new Date(); // 重复调用幂等静默：revokedAt 已置仍更新 replacedBy 口径不敏感
      token.replacedBy = replacedBy;
    }
    return Promise.resolve();
  }

  revokeUserRefreshTokens(userId: string, deviceId?: string): Promise<number> {
    let count = 0;
    for (const t of this.store.refreshTokens.values()) {
      if (t.userId === userId && !t.revokedAt && (!deviceId || t.deviceId === deviceId)) {
        t.revokedAt = new Date();
        count += 1;
      }
    }
    return Promise.resolve(count);
  }

  // ===== 断食方案 =====

  listFastingPlansByUser(userId: string): Promise<FastingPlanEntity[]> {
    return Promise.resolve(
      [...this.store.fastingPlans.values()].filter((p) => p.userId === userId),
    );
  }

  saveFastingPlan(plan: FastingPlanEntity): Promise<void> {
    this.store.fastingPlans.set(plan.id, plan);
    return Promise.resolve();
  }

  // ===== 断食记录 =====

  findFastingRecordById(id: string): Promise<FastingRecordEntity | null> {
    return Promise.resolve(this.store.fastingRecords.get(id) ?? null);
  }

  findFastingRecordByPlannedEnd(
    userId: string,
    plannedEndAt: Date,
  ): Promise<FastingRecordEntity | null> {
    const row = [...this.store.fastingRecords.values()].find(
      (r) => r.userId === userId && r.plannedEndAt.getTime() === plannedEndAt.getTime(),
    );
    return Promise.resolve(row ?? null);
  }

  findOngoingFastingRecord(userId: string): Promise<FastingRecordEntity | null> {
    const row = [...this.store.fastingRecords.values()]
      .filter((r) => r.userId === userId && r.result === 'on_track')
      .sort((a, b) => b.plannedEndAt.getTime() - a.plannedEndAt.getTime())[0];
    return Promise.resolve(row ?? null);
  }

  listFastingRecordsByUser(userId: string): Promise<FastingRecordEntity[]> {
    return Promise.resolve(
      [...this.store.fastingRecords.values()].filter((r) => r.userId === userId),
    );
  }

  saveFastingRecord(record: FastingRecordEntity): Promise<void> {
    this.store.fastingRecords.set(record.id, record);
    return Promise.resolve();
  }

  // ===== 食物库 =====

  findFoodById(id: string): Promise<FoodEntity | null> {
    return Promise.resolve(this.store.foods.get(id) ?? null);
  }

  /** 内存 foods 表即共享/内置库（自定义在 customFoods），结构性排除 isCustom */
  findFoodByBarcode(barcode: string): Promise<FoodEntity | null> {
    const row = [...this.store.foods.values()].find((f) => f.barcode === barcode);
    return Promise.resolve(row ?? null);
  }

  createCustomFood(food: CustomFoodEntity): Promise<void> {
    this.store.customFoods.set(food.id, food);
    return Promise.resolve();
  }

  findCustomFoodById(id: string): Promise<CustomFoodEntity | null> {
    return Promise.resolve(this.store.customFoods.get(id) ?? null);
  }

  findCustomFoodsByUser(userId: string): Promise<CustomFoodEntity[]> {
    return Promise.resolve([...this.store.customFoods.values()].filter((f) => f.userId === userId));
  }

  deleteCustomFood(id: string): Promise<void> {
    this.store.customFoods.delete(id);
    return Promise.resolve();
  }

  searchFoods(
    q: string,
    userId?: string,
    _locale?: string,
    limit?: number,
  ): Promise<FoodSearchHit[]> {
    const ql = q.trim().toLowerCase();
    if (!ql) return Promise.resolve([]);
    const raw = q.trim();
    const builtIn: FoodSearchHit[] = [];
    for (const food of this.store.foods.values()) {
      const hit = this.matchFood(food, raw, ql, false);
      if (hit) builtIn.push(hit);
    }
    builtIn.sort((a, b) => b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh));
    const custom: FoodSearchHit[] = [];
    if (userId) {
      for (const food of this.store.customFoods.values()) {
        if (food.userId !== userId) continue;
        const hit = this.matchFood(food, raw, ql, true);
        if (hit) custom.push(hit);
      }
      custom.sort((a, b) => b.score - a.score || a.food.nameZh.localeCompare(b.food.nameZh));
    }
    const all = [...builtIn, ...custom];
    return Promise.resolve(limit != null ? all.slice(0, limit) : all);
  }

  findFoodCandidateById(id: string): Promise<FoodCandidateEntity | null> {
    return Promise.resolve(this.store.foodCandidates.get(id) ?? null);
  }

  listFoodCandidates(status?: FoodCandidateStatus): Promise<FoodCandidateEntity[]> {
    const rows = [...this.store.foodCandidates.values()]
      .filter((c) => !status || c.status === status)
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime() || a.id.localeCompare(b.id));
    return Promise.resolve(rows);
  }

  findFoodCandidatesByUser(
    userId: string,
    status?: FoodCandidateStatus,
  ): Promise<FoodCandidateEntity[]> {
    const rows = [...this.store.foodCandidates.values()]
      .filter((c) => c.userId === userId && (!status || c.status === status))
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime() || b.id.localeCompare(a.id));
    return Promise.resolve(rows);
  }

  findFoodCandidateByFoodId(foodId: string): Promise<FoodCandidateEntity | null> {
    const row = [...this.store.foodCandidates.values()].find((c) => c.foodId === foodId);
    return Promise.resolve(row ?? null);
  }

  findFoodCandidateByBarcode(barcode: string): Promise<FoodCandidateEntity | null> {
    const blocking = [...this.store.foodCandidates.values()]
      .filter((c) => c.barcode === barcode && c.status !== 'rejected')
      .sort((a, b) => {
        // pending 优先于 approved，同级 createdAt 升序取最早一条
        const rank = (c: FoodCandidateEntity) => (c.status === 'pending' ? 0 : 1);
        return rank(a) - rank(b) || a.createdAt.getTime() - b.createdAt.getTime();
      });
    return Promise.resolve(blocking[0] ?? null);
  }

  /** 与 food.service.reviewFoodCandidate approve 分支同口径：id 不变，转共享并移出个人库 */
  promoteCustomFoodToShared(foodId: string, barcode?: string | null): Promise<void> {
    const custom = this.store.customFoods.get(foodId);
    if (!custom) return Promise.reject(err.notFound());
    this.store.customFoods.delete(foodId);
    this.store.foods.set(foodId, {
      id: custom.id,
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
      barcode: barcode ?? null,
    });
    return Promise.resolve();
  }

  // ===== 饮食记录 =====

  findFoodEntryById(id: string): Promise<FoodEntryEntity | null> {
    return Promise.resolve(this.store.foodEntries.get(id) ?? null);
  }

  findFoodEntryByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<FoodEntryEntity | null> {
    const row = [...this.store.foodEntries.values()].find(
      (e) => e.userId === userId && e.clientRequestId === clientRequestId,
    );
    return Promise.resolve(row ?? null);
  }

  listFoodEntriesByUser(userId: string): Promise<FoodEntryEntity[]> {
    const rows = [...this.store.foodEntries.values()]
      .filter((e) => e.userId === userId)
      .sort((a, b) => a.updatedAt.getTime() - b.updatedAt.getTime() || a.id.localeCompare(b.id));
    return Promise.resolve(rows);
  }

  saveFoodEntry(entry: FoodEntryEntity): Promise<void> {
    this.store.foodEntries.set(entry.id, entry);
    return Promise.resolve();
  }

  // ===== Streak =====

  findStreakByUser(userId: string): Promise<StreakEntity | null> {
    return Promise.resolve(this.store.streaks.get(userId) ?? null);
  }

  saveStreak(streak: StreakEntity): Promise<void> {
    this.store.streaks.set(streak.userId, streak);
    return Promise.resolve();
  }

  // ===== 幂等表 =====

  findIdempotencyRecord(
    userId: string,
    endpoint: string,
    clientRequestId: string,
  ): Promise<IdempotencyRecord | null> {
    return Promise.resolve(
      this.store.idempotency.get(this.store.idemKey(userId, endpoint, clientRequestId)) ?? null,
    );
  }

  saveIdempotencyRecord(record: IdempotencyRecord): Promise<void> {
    this.store.idempotency.set(
      this.store.idemKey(record.userId, record.endpoint, record.clientRequestId),
      record,
    );
    return Promise.resolve();
  }

  // ===== 打卡帖 =====

  findPostById(id: string): Promise<PostEntity | null> {
    return Promise.resolve(this.store.posts.get(id) ?? null);
  }

  savePost(post: PostEntity): Promise<void> {
    this.store.posts.set(post.id, post);
    return Promise.resolve();
  }

  findFeedPosts(viewerId: string): Promise<PostEntity[]> {
    const rows = [...this.store.posts.values()]
      .filter((p) => !p.deletedAt)
      .filter((p) => p.auditStatus === 'approved' || p.userId === viewerId)
      .sort((a, b) => this.compareDesc(a, b));
    return Promise.resolve(rows);
  }

  listPostsForAdmin(filter: PostAdminFilter | undefined): Promise<PostEntity[]> {
    const match = (p: PostEntity): boolean => {
      switch (filter) {
        case 'pending':
          return p.auditStatus === 'pending';
        case 'approved':
          return p.auditStatus === 'approved';
        case 'rejected':
          return p.auditStatus === 'rejected' && p.reportCount === 0;
        case 'reported':
          return p.auditStatus === 'rejected' && p.reportCount > 0;
        default:
          return true;
      }
    };
    const rows = [...this.store.posts.values()]
      .filter((p) => !p.deletedAt)
      .filter(match)
      .sort((a, b) => this.compareDesc(a, b));
    return Promise.resolve(rows);
  }

  likePost(postId: string, userId: string): Promise<void> {
    const post = this.store.posts.get(postId);
    if (!post) return Promise.reject(err.notFound());
    const key = this.store.postLikeKey(postId, userId);
    if (!this.store.postLikes.has(key)) {
      this.store.postLikes.add(key);
      post.likeCount += 1;
      post.updatedAt = new Date();
      post.version += 1;
    }
    return Promise.resolve();
  }

  unlikePost(postId: string, userId: string): Promise<void> {
    const post = this.store.posts.get(postId);
    if (!post) return Promise.reject(err.notFound());
    const key = this.store.postLikeKey(postId, userId);
    if (this.store.postLikes.delete(key)) {
      post.likeCount = Math.max(0, post.likeCount - 1);
      post.updatedAt = new Date();
      post.version += 1;
    }
    return Promise.resolve();
  }

  hasPostLike(postId: string, userId: string): Promise<boolean> {
    return Promise.resolve(this.store.postLikes.has(this.store.postLikeKey(postId, userId)));
  }

  hasPostReport(postId: string, userId: string): Promise<boolean> {
    return Promise.resolve(this.store.postReports.has(this.store.postLikeKey(postId, userId)));
  }

  createPostReport(postId: string, userId: string, reason?: string | null): Promise<void> {
    const key = this.store.postLikeKey(postId, userId);
    if (!this.store.postReports.has(key)) {
      this.store.postReports.set(key, { reason: reason ?? null, createdAt: new Date() });
    }
    return Promise.resolve(); // 唯一冲突 = 幂等重放静默
  }

  private matchFood(
    food: FoodEntity | CustomFoodEntity,
    q: string,
    ql: string,
    isCustom: boolean,
  ): FoodSearchHit | null {
    // 与 food.service.matchFood 同口径：前缀 3 > 子串 2 > 别名 1
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

  // ===== 人工审核队列 =====

  enqueueModerationItem(item: ModerationQueueItem): Promise<void> {
    this.store.moderationQueue.push({ ...item });
    return Promise.resolve();
  }

  listModerationQueue(): Promise<ModerationQueueItem[]> {
    return Promise.resolve([...this.store.moderationQueue]);
  }

  removeModerationByPost(postId: string): Promise<number> {
    let removed = 0;
    for (let i = this.store.moderationQueue.length - 1; i >= 0; i--) {
      if (this.store.moderationQueue[i].postId === postId) {
        this.store.moderationQueue.splice(i, 1);
        removed += 1;
      }
    }
    return Promise.resolve(removed);
  }

  // ===== 管理员账号 =====

  countAdminUsers(): Promise<number> {
    return Promise.resolve(this.store.adminUsers.size);
  }

  findAdminByUsername(username: string): Promise<AdminUserEntity | null> {
    return Promise.resolve(this.store.findAdminByUsername(username) ?? null);
  }

  findAdminById(id: string): Promise<AdminUserEntity | null> {
    return Promise.resolve(this.store.adminUsers.get(id) ?? null);
  }

  createAdminUser(partial: Omit<AdminUserEntity, 'id' | 'createdAt'>): Promise<AdminUserEntity> {
    return Promise.resolve(this.store.createAdminUser(partial));
  }

  private mustGetUser(userId: string): UserEntity {
    const user = this.store.users.get(userId);
    if (!user || user.deletedAt) throw err.notFound();
    return user;
  }

  private compareDesc(a: PostEntity, b: PostEntity): number {
    const t = b.createdAt.getTime() - a.createdAt.getTime();
    return t !== 0 ? t : b.id.localeCompare(a.id);
  }

  private findWaterByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): WaterLogEntity | undefined {
    return [...this.store.waterLogs.values()].find(
      (e) => e.userId === userId && e.clientRequestId === clientRequestId,
    );
  }

  private findFoodCandidateByUserAndRequestIdSync(
    userId: string,
    clientRequestId: string,
  ): FoodCandidateEntity | undefined {
    return [...this.store.foodCandidates.values()].find(
      (e) => e.userId === userId && e.clientRequestId === clientRequestId,
    );
  }
}
