import { Injectable } from '@nestjs/common';
import { newId } from '../utils/id.util';

// ===== 实体类型（与 prisma/schema.prisma 对齐）=====

export interface UserEntity {
  id: string;
  phone: string | null;
  nickname: string | null;
  gender: string | null;
  birthYear: number | null;
  heightCm: number | null;
  weightKg: number | null;
  activityLevel: string | null;
  goal: string | null;
  locale: string;
  timezone: string;
  themePref: string;
  accessibilityPrefs: Record<string, unknown> | null;
  onboardingStatus: string;
  deletionStatus: string | null;
  version: number;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

export interface RefreshTokenEntity {
  id: string;
  userId: string;
  tokenHash: string;
  deviceId: string | null;
  expiresAt: Date;
  revokedAt: Date | null;
  replacedBy: string | null;
  createdAt: Date;
}

export interface FastingPlanEntity {
  id: string;
  userId: string;
  planType: string;
  eatingWindowStart: string;
  eatingWindowEnd: string;
  effectiveDate: string;
  status: 'current' | 'pending' | 'expired';
  clientRequestId: string | null;
  version: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface FastingRecordEntity {
  id: string;
  userId: string;
  attributionDate: string;
  plannedStartAt: Date;
  plannedEndAt: Date;
  actualStartAt: Date | null;
  actualEndAt: Date | null;
  extendedMinutes: number;
  fastedMinutes: number | null;
  result: 'on_track' | 'completed' | 'ended_early' | 'broken' | 'makeup';
  isQualified: boolean;
  eventLog: Array<{ at: string; event: string; detail?: Record<string, unknown> }>;
  clientRequestId: string | null;
  version: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface FoodEntity {
  id: string;
  nameZh: string;
  nameEn: string;
  aliases: string[];
  kcalPer100g: number;
  proteinPer100g: number;
  carbsPer100g: number;
  fatPer100g: number;
  category: string;
  source: string;
}

export interface NutritionSnapshot {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

export interface FoodEntryEntity {
  id: string;
  userId: string;
  clientRequestId: string;
  eatenAt: Date;
  foodId: string;
  grams: number;
  inputMethod: string;
  photoUrl: string | null;
  nutritionSnapshot: NutritionSnapshot;
  version: number;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

export interface MakeupCards {
  stock: number;
  month: string; // YYYY-MM（用户 timezone）
  usedDates: string[];
}

export interface StreakEntity {
  id: string;
  userId: string;
  currentStreak: number;
  longestStreak: number;
  lastQualifiedDate: string | null;
  milestones: Record<string, string>;
  makeupCards: MakeupCards;
  version: number;
  updatedAt: Date;
}

export type AuditStatus = 'pending' | 'approved' | 'rejected';

/** 打卡帖（契约 §3.9 / Post 实体，先审后发 D-17） */
export interface PostEntity {
  id: string;
  userId: string;
  clientRequestId: string | null;
  text: string;
  imageUrls: string[];
  /** 发布时的连续达标天数（服务端权威计算，D-12 口径） */
  streakDaysAtPost: number | null;
  likeCount: number;
  auditStatus: AuditStatus;
  /** 双语审核原因（rejected 时展示给作者） */
  auditReason: { zh: string; en: string } | null;
  visibility: string; // self / followers / public 预留
  version: number;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

/** 审核队列条目（机审异常/疑似 与 举报复核共用，D-17 转人工） */
export interface ModerationQueueItem {
  postId: string;
  source: 'auto' | 'report';
  reason: string;
  createdAt: Date;
}

export interface IdempotencyRecord {
  userId: string;
  clientRequestId: string;
  endpoint: string;
  payloadHash: string;
  responseBody: unknown;
  createdAt: Date;
}

/**
 * 内存数据层。〔假设〕M0 骨架阶段：接口行为按契约实现，持久化后置 —
 * Prisma schema 已就位（prisma/schema.prisma），接入真实 PostgreSQL 时
 * 将各 Service 的读写替换为 PrismaClient 仓储即可，Service 对外契约不变。
 */
@Injectable()
export class DataStore {
  readonly users = new Map<string, UserEntity>();
  readonly refreshTokens = new Map<string, RefreshTokenEntity>(); // key: tokenHash
  readonly fastingPlans = new Map<string, FastingPlanEntity>();
  readonly fastingRecords = new Map<string, FastingRecordEntity>();
  readonly foods = new Map<string, FoodEntity>();

  /** 已加载的 foods.seed.json 版本号（D-16 全量库幂等加载标记，见 food-seed-loader.ts）。 */
  foodSeedVersion: string | null = null;
  readonly foodEntries = new Map<string, FoodEntryEntity>();
  readonly streaks = new Map<string, StreakEntity>(); // key: userId
  readonly idempotency = new Map<string, IdempotencyRecord>(); // key: userId|endpoint|clientRequestId

  /** 打卡帖（M5 P1） */
  readonly posts = new Map<string, PostEntity>();
  /** 点赞幂等键（契约 §四：postId+userId 唯一约束） */
  readonly postLikes = new Set<string>(); // key: postId|userId
  /** 举报幂等键（同用户同帖一次） */
  readonly postReports = new Map<string, { reason: string | null; createdAt: Date }>(); // key: postId|userId
  /** 人工审核队列（机审疑似 + 举报复核，D-17） */
  readonly moderationQueue: ModerationQueueItem[] = [];

  postLikeKey(postId: string, userId: string): string {
    return `${postId}|${userId}`;
  }

  /** 短信验证码（〔假设〕mock：固定 123456，生产应落 Redis 并接短信通道） */
  readonly smsCodes = new Map<string, { code: string; sentAt: Date; attempts: number }>();

  constructor() {
    this.seedFoods();
  }

  idemKey(userId: string, endpoint: string, clientRequestId: string): string {
    return `${userId}|${endpoint}|${clientRequestId}`;
  }

  findUserByPhone(phone: string): UserEntity | undefined {
    return [...this.users.values()].find((u) => u.phone === phone && !u.deletedAt);
  }

  createUser(partial: Partial<UserEntity>): UserEntity {
    const now = new Date();
    const user: UserEntity = {
      id: newId(),
      phone: null,
      nickname: null,
      gender: null,
      birthYear: null,
      heightCm: null,
      weightKg: null,
      activityLevel: null,
      goal: null,
      locale: 'zh-CN',
      timezone: 'Asia/Shanghai',
      themePref: 'system',
      accessibilityPrefs: null,
      onboardingStatus: 'none',
      deletionStatus: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      ...partial,
    };
    this.users.set(user.id, user);
    return user;
  }

  /** 食物库种子数据（〔假设〕示例条目；正式库 ≥3000 条由《中国食物成分表》+ USDA FDC 清洗导入，D-16） */
  private seedFoods() {
    const seeds: Array<Omit<FoodEntity, 'id'>> = [
      {
        nameZh: '鸡蛋',
        nameEn: 'Egg',
        aliases: ['ji dan', '鸡蛋(煮)', 'boiled egg'],
        kcalPer100g: 144,
        proteinPer100g: 13.3,
        carbsPer100g: 2.8,
        fatPer100g: 8.8,
        category: '蛋制品',
        source: 'cn_fct',
      },
      {
        nameZh: '鸡胸肉',
        nameEn: 'Chicken Breast',
        aliases: ['ji xiong rou'],
        kcalPer100g: 118,
        proteinPer100g: 24.6,
        carbsPer100g: 0.6,
        fatPer100g: 1.9,
        category: '畜禽肉',
        source: 'cn_fct',
      },
      {
        nameZh: '米饭',
        nameEn: 'Rice (Cooked)',
        aliases: ['mi fan', 'steamed rice', '白米饭'],
        kcalPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
        category: '谷薯类',
        source: 'cn_fct',
      },
      {
        nameZh: '燕麦',
        nameEn: 'Oats',
        aliases: ['yan mai', 'oatmeal'],
        kcalPer100g: 377,
        proteinPer100g: 15.0,
        carbsPer100g: 66.9,
        fatPer100g: 6.7,
        category: '谷薯类',
        source: 'usda',
      },
      {
        nameZh: '苹果',
        nameEn: 'Apple',
        aliases: ['ping guo'],
        kcalPer100g: 53,
        proteinPer100g: 0.4,
        carbsPer100g: 13.7,
        fatPer100g: 0.3,
        category: '水果',
        source: 'cn_fct',
      },
      {
        nameZh: '西兰花',
        nameEn: 'Broccoli',
        aliases: ['xi lan hua', 'green cauliflower'],
        kcalPer100g: 36,
        proteinPer100g: 4.1,
        carbsPer100g: 4.3,
        fatPer100g: 0.6,
        category: '蔬菜',
        source: 'usda',
      },
      {
        nameZh: '牛奶',
        nameEn: 'Milk',
        aliases: ['niu nai', 'whole milk'],
        kcalPer100g: 65,
        proteinPer100g: 3.3,
        carbsPer100g: 4.8,
        fatPer100g: 3.6,
        category: '乳制品',
        source: 'cn_fct',
      },
      {
        nameZh: '三文鱼',
        nameEn: 'Salmon',
        aliases: ['san wen yu'],
        kcalPer100g: 208,
        proteinPer100g: 20.4,
        carbsPer100g: 0,
        fatPer100g: 13.4,
        category: '水产',
        source: 'usda',
      },
    ];
    for (const s of seeds) {
      const food: FoodEntity = { id: `f_${newId().slice(0, 8)}`, ...s };
      this.foods.set(food.id, food);
    }
  }
}
