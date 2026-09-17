import { Injectable } from '@nestjs/common';
import { UserEntity } from '../common/store/data-store';

export interface NutritionTargets {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  fallback: boolean;
  /** 阶段 B：缺口法生效时的减重计划信息（weeklyRateKg/dailyDeficitKcal/clamped/预计达成日） */
  weightLoss?: WeightLossPlanResult;
}

const ACTIVITY_FACTOR: Record<string, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  high: 1.725,
};

/** 1 kg 体脂 ≈ 7700 kcal（阶段 B 缺口法换算系数，待营养侧书面背书） */
export const KCAL_PER_KG = 7700;

/** 周减重速率安全边界（kg/周）：上限 1.0、下限 0.1（待营养侧书面背书） */
export const WEEKLY_RATE_MAX_KG = 1.0;
export const WEEKLY_RATE_MIN_KG = 0.1;

export interface WeightLossPlanResult {
  /** 周减重速率（kg/周，夹取到 [0.1, 1.0]） */
  weeklyRateKg: number;
  /** 日热量缺口（kcal） */
  dailyDeficitKcal: number;
  /** 缺口法每日热量目标（kcal，含下限保护，未取整） */
  targetKcal: number;
  /** 原始速率超安全上限被夹取（UI 提示「已按安全上限调整」） */
  clamped: boolean;
  /** 预计达成日期（YYYY-MM-DD，按夹取后速率折算） */
  reachDate: string;
}

/**
 * 阶段 B 减重速率→热量缺口（叠加在 D-04 之上；待营养侧书面背书）：
 * 目标体重 < 当前体重且目标日期在未来时生效——weeklyRate = 体重差 ÷ 周数，
 * 夹取到 [0.1, 1.0] kg/周；dailyDeficit = weeklyRate × 7700 ÷ 7；
 * targetKcal = TDEE − dailyDeficit，不破下限（女 1200 / 男 1500）。
 * 输入不满足（无目标/目标≥当前/目标日期非未来）返回 null → 调用方回落 TDEE×0.8。
 */
export function computeWeightLossPlan(input: {
  currentWeightKg: number;
  targetWeightKg?: number | null;
  targetDate?: Date | null;
  tdee: number;
  minKcal: number;
  now?: Date;
}): WeightLossPlanResult | null {
  const { currentWeightKg, targetWeightKg, targetDate, tdee, minKcal } = input;
  if (targetWeightKg == null || targetDate == null) return null;
  if (targetWeightKg >= currentWeightKg) return null; // 增重/维持不走缺口法
  const now = input.now ?? new Date();
  const todayUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const daysToTarget = Math.round((targetDate.getTime() - todayUtc) / 86400000);
  if (daysToTarget <= 0) return null;

  const deltaKg = currentWeightKg - targetWeightKg;
  const rawRate = deltaKg / (daysToTarget / 7);
  const clamped = rawRate > WEEKLY_RATE_MAX_KG;
  const weeklyRateKg = Math.min(WEEKLY_RATE_MAX_KG, Math.max(WEEKLY_RATE_MIN_KG, rawRate));
  const dailyDeficitKcal = (weeklyRateKg * KCAL_PER_KG) / 7;
  const targetKcal = Math.max(tdee - dailyDeficitKcal, minKcal);
  const daysToReach = Math.ceil((deltaKg / weeklyRateKg) * 7);
  const reachDate = new Date(todayUtc + daysToReach * 86400000).toISOString().slice(0, 10);
  return { weeklyRateKg, dailyDeficitKcal, targetKcal, clamped, reachDate };
}

/**
 * D-04 TDEE 公式（待营养侧书面背书，规则热配置前置为纯函数）：
 * BMR = Mifflin-St Jeor；TDEE = BMR × 活动系数；减脂 ×0.8，下限 女1200/男1500；
 * 供能比 蛋白25% / 碳水45% / 脂肪30%（4/4/9 kcal/g）。
 * 阶段 B：fat_loss 且有目标体重+未来目标日期 → 缺口法替代固定 ×0.8
 * （computeWeightLossPlan，速率超上限 clamped=true）。
 */
export function computeTargets(
  user: Pick<
    UserEntity,
    | 'gender'
    | 'birthYear'
    | 'heightCm'
    | 'weightKg'
    | 'activityLevel'
    | 'goal'
    | 'targetWeightKg'
    | 'targetDate'
  >,
): NutritionTargets {
  const missing = !user.gender || !user.birthYear || !user.heightCm || !user.weightKg;
  if (missing) {
    // 缺基础信息兜底：女 1800 / 男 2200 / 性别未知 2000（与客户端
    // NutritionRuleConfig.fallbackUnknownKcal 口径一致，规格 §1.6），引导补全资料
    const kcal = user.gender === 'male' ? 2200 : user.gender === 'female' ? 1800 : 2000;
    return { ...macroSplit(kcal), fallback: true };
  }
  const age = new Date().getUTCFullYear() - (user.birthYear as number);
  const base = 10 * (user.weightKg as number) + 6.25 * (user.heightCm as number) - 5 * age;
  const bmr = user.gender === 'male' ? base + 5 : base - 161;
  const tdee = bmr * (ACTIVITY_FACTOR[user.activityLevel ?? 'sedentary'] ?? 1.2);
  const floor = user.gender === 'male' ? 1500 : 1200;
  let weightLoss: WeightLossPlanResult | null = null;
  if (user.goal === 'fat_loss') {
    weightLoss = computeWeightLossPlan({
      currentWeightKg: user.weightKg as number,
      targetWeightKg: user.targetWeightKg,
      targetDate: user.targetDate,
      tdee,
      minKcal: floor,
    });
  }
  let kcal: number;
  if (weightLoss) {
    kcal = weightLoss.targetKcal;
  } else {
    kcal = user.goal === 'fat_loss' ? tdee * 0.8 : tdee;
    kcal = Math.max(kcal, floor);
  }
  return { ...macroSplit(Math.round(kcal)), fallback: false, weightLoss: weightLoss ?? undefined };
}

function macroSplit(kcal: number) {
  return {
    kcal,
    proteinG: Math.round((kcal * 0.25) / 4),
    carbsG: Math.round((kcal * 0.45) / 4),
    fatG: Math.round((kcal * 0.3) / 9),
  };
}

export interface Signal {
  nutrient: 'kcal' | 'protein' | 'carbs' | 'fat';
  level: 'green' | 'yellow' | 'red';
  percent: number;
  adviceKey: string;
}

/** D-05 红黄绿信号灯阈值（以摄入 ÷ 目标百分比；待营养侧书面背书） */
const THRESHOLDS: Record<
  Signal['nutrient'],
  { green: [number, number]; yellow: [number, number][]; redOver?: number }
> = {
  kcal: {
    green: [85, 110],
    yellow: [
      [60, 85],
      [110, 130],
    ],
  },
  protein: { green: [90, 150], yellow: [[70, 90]], redOver: 150 },
  carbs: {
    green: [85, 115],
    yellow: [
      [65, 85],
      [115, 135],
    ],
  },
  fat: {
    green: [80, 110],
    yellow: [
      [55, 80],
      [110, 130],
    ],
  },
};

export function computeSignals(
  totals: { kcal: number; proteinG: number; carbsG: number; fatG: number },
  targets: NutritionTargets,
): Signal[] {
  const pairs: Array<[Signal['nutrient'], number, number]> = [
    ['kcal', totals.kcal, targets.kcal],
    ['protein', totals.proteinG, targets.proteinG],
    ['carbs', totals.carbsG, targets.carbsG],
    ['fat', totals.fatG, targets.fatG],
  ];
  return pairs.map(([nutrient, actual, target]) => {
    const percent = target > 0 ? Math.round((actual / target) * 100) : 0;
    const t = THRESHOLDS[nutrient];
    let level: Signal['level'] = 'red';
    if (percent >= t.green[0] && percent <= t.green[1]) level = 'green';
    else if (t.yellow.some(([lo, hi]) => percent >= lo && percent < hi)) level = 'yellow';
    // 方向按 percent 相对 green 区间判定：偏高黄灯（如 kcal 110–130%）是「吃多了」而非「吃少了」
    const zone = level === 'green' ? 'ok' : percent > t.green[1] ? 'high' : 'low';
    return { nutrient, level, percent, adviceKey: `advice.${nutrient}.${zone}` };
  });
}

@Injectable()
export class NutritionService {}
