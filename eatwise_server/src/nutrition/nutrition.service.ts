import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore } from '../common/store/data-store';
import { isValidDateStr, localDateOf } from '../common/utils/time.util';
import { computeSignals, computeTargets } from './nutrition.rules';

@Injectable()
export class NutritionService {
  constructor(private readonly store: DataStore) {}

  /** N1 当日 DailyNutrition + 四营养素信号灯（D-04/D-05，服务端聚合） */
  daily(userId: string, date: string, tz: string) {
    if (!isValidDateStr(date)) throw err.validation({ date: 'invalid local date' });
    const totals = this.aggregate(userId, date, tz);
    const user = this.store.users.get(userId);
    const targets = computeTargets(user ?? ({} as never));
    const hasData = totals.count > 0;
    return {
      date,
      hasData,
      totals: {
        kcal: totals.kcal,
        proteinG: totals.proteinG,
        carbsG: totals.carbsG,
        fatG: totals.fatG,
      },
      targets,
      signals: hasData
        ? computeSignals(
            {
              kcal: totals.kcal,
              proteinG: totals.proteinG,
              carbsG: totals.carbsG,
              fatG: totals.fatG,
            },
            targets,
          )
        : [],
    };
  }

  /** 按本地日聚合 FoodEntry（未软删） */
  aggregate(userId: string, date: string, tz: string) {
    const totals = { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, count: 0 };
    for (const e of this.store.foodEntries.values()) {
      if (e.userId !== userId || e.deletedAt) continue;
      if (localDateOf(e.eatenAt, tz) !== date) continue;
      totals.kcal += e.nutritionSnapshot.kcal;
      totals.proteinG += e.nutritionSnapshot.proteinG;
      totals.carbsG += e.nutritionSnapshot.carbsG;
      totals.fatG += e.nutritionSnapshot.fatG;
      totals.count += 1;
    }
    totals.kcal = round1(totals.kcal);
    totals.proteinG = round1(totals.proteinG);
    totals.carbsG = round1(totals.carbsG);
    totals.fatG = round1(totals.fatG);
    return totals;
  }
}

export function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
