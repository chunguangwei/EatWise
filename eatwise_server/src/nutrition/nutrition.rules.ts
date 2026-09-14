import { Injectable } from '@nestjs/common';
import { UserEntity } from '../common/store/data-store';

export interface NutritionTargets {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  fallback: boolean;
}

const ACTIVITY_FACTOR: Record<string, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  high: 1.725,
};

/**
 * D-04 TDEE 公式（待营养侧书面背书，规则热配置前置为纯函数）：
 * BMR = Mifflin-St Jeor；TDEE = BMR × 活动系数；减脂 ×0.8，下限 女1200/男1500；
 * 供能比 蛋白25% / 碳水45% / 脂肪30%（4/4/9 kcal/g）。
 */
export function computeTargets(
  user: Pick<
    UserEntity,
    'gender' | 'birthYear' | 'heightCm' | 'weightKg' | 'activityLevel' | 'goal'
  >,
): NutritionTargets {
  const missing = !user.gender || !user.birthYear || !user.heightCm || !user.weightKg;
  if (missing) {
    // 缺基础信息兜底：女 1800 / 男 2200（性别未知按 1800），引导补全资料
    const kcal = user.gender === 'male' ? 2200 : 1800;
    return { ...macroSplit(kcal), fallback: true };
  }
  const age = new Date().getUTCFullYear() - (user.birthYear as number);
  const base = 10 * (user.weightKg as number) + 6.25 * (user.heightCm as number) - 5 * age;
  const bmr = user.gender === 'male' ? base + 5 : base - 161;
  const tdee = bmr * (ACTIVITY_FACTOR[user.activityLevel ?? 'sedentary'] ?? 1.2);
  let kcal = user.goal === 'fat_loss' ? tdee * 0.8 : tdee;
  const floor = user.gender === 'male' ? 1500 : 1200;
  kcal = Math.max(kcal, floor);
  return { ...macroSplit(Math.round(kcal)), fallback: false };
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
