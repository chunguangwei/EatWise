import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { FastingRecordEntity, StreakEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { addDays, isValidDateStr, localDateOf, localMonthOf } from '../common/utils/time.util';

const MONTHLY_GRANT = 2; // 每月 1 日发放 2 张（D-12）
const STOCK_CAP = 2; // 库存上限 2 张，不累积（D-12）
const MAKEUP_WINDOW_DAYS = 7; // 仅可补最近 7 天内的断签日（D-12）
const MILESTONES = [3, 7, 30];

/**
 * Streak 与补签卡（D-12）：口径 = 断食打卡达标，服务端权威计算。
 */
@Injectable()
export class StreakService {
  constructor(@Inject(STORE_DRIVER) private readonly driver: StoreDriver) {}

  private async tzOf(userId: string, driver: StoreDriver = this.driver): Promise<string> {
    return (await driver.findUserById(userId))?.timezone ?? 'Asia/Shanghai';
  }

  /** 读取（不存在则初始化），并执行月度 rollover：当月有效、月底清零、月初发 2 张（上限 2） */
  async getOrCreate(
    userId: string,
    tz?: string,
    driver: StoreDriver = this.driver,
  ): Promise<StreakEntity> {
    return driver.runInTransaction([`streak:${userId}`], async (tx) => {
      const zone = tz ?? (await this.tzOf(userId, tx));
      const now = new Date();
      let streak = await tx.findStreakByUser(userId);
      let changed = false;
      if (!streak) {
        streak = {
          id: newId(),
          userId,
          currentStreak: 0,
          longestStreak: 0,
          lastQualifiedDate: null,
          milestones: {},
          makeupCards: { stock: MONTHLY_GRANT, month: localMonthOf(now, zone), usedDates: [] },
          version: 1,
          updatedAt: now,
        };
        changed = true;
      }
      const currentMonth = localMonthOf(now, zone);
      if (streak.makeupCards.month !== currentMonth) {
        streak.makeupCards = {
          stock: MONTHLY_GRANT,
          month: currentMonth,
          usedDates: [],
        };
        streak.updatedAt = now;
        changed = true;
      } else if (streak.makeupCards.stock > STOCK_CAP) {
        streak.makeupCards.stock = STOCK_CAP;
        streak.updatedAt = now;
        changed = true;
      }
      if (changed) await tx.saveStreak(streak);
      return streak;
    });
  }

  /** 达标日期集合：断食达标（D-08）或补签日 */
  async qualifiedDates(userId: string, driver: StoreDriver = this.driver): Promise<Set<string>> {
    const dates = new Set<string>();
    for (const r of await driver.listFastingRecordsByUser(userId)) {
      if (r.deletedAt) continue; // /sync delete tombstone 不计入达标集合
      if (r.isQualified || r.result === 'makeup') dates.add(r.attributionDate);
    }
    return dates;
  }

  /** 由达标日重算 streak（中断 → 当前 streak 归零，D-12） */
  async recompute(
    userId: string,
    driver: StoreDriver = this.driver,
    timezone?: string,
  ): Promise<StreakEntity> {
    return driver.runInTransaction([`streak:${userId}`], async (tx) => {
      const zone = timezone ?? (await this.tzOf(userId, tx));
      const streak = await this.getOrCreate(userId, zone, tx);
      const dates = [...(await this.qualifiedDates(userId, tx))].sort();
      const now = new Date();
      const today = localDateOf(now, zone);
      const yesterday = addDays(today, -1);

      let current = 0;
      if (dates.length) {
        const last = dates[dates.length - 1];
        if (last === today || last === yesterday) {
          current = 1;
          for (let i = dates.length - 2; i >= 0; i--) {
            if (dates[i] === addDays(dates[i + 1], -1)) current += 1;
            else break;
          }
        }
      }
      let longest = 0;
      let run = 0;
      for (let i = 0; i < dates.length; i++) {
        run = i > 0 && dates[i] === addDays(dates[i - 1], 1) ? run + 1 : 1;
        longest = Math.max(longest, run);
      }

      streak.currentStreak = current;
      streak.longestStreak = Math.max(streak.longestStreak, longest);
      streak.lastQualifiedDate = dates.length ? dates[dates.length - 1] : null;
      // 里程碑：currentStreak 跨越 3/7/30 时写入（D-12）
      for (const m of MILESTONES) {
        if (current >= m && !streak.milestones[String(m)]) {
          streak.milestones[String(m)] = now.toISOString();
        }
      }
      streak.version += 1;
      streak.updatedAt = now;
      await tx.saveStreakStats(streak);
      return streak;
    });
  }

  /** S2 使用补签卡（D-12 规则表，服务端强制执行） */
  async makeUp(userId: string, clientRequestId: string, date: string, timezone?: string) {
    const endpoint = 'streak/makeup';
    const hash = payloadHash({ date });
    if (!isValidDateStr(date)) throw err.validation({ date: 'invalid date' });
    return this.driver.runInTransaction(
      [
        `fasting:${userId}`,
        `idempotency:${userId}:${endpoint}:${clientRequestId}`,
        `streak:${userId}`,
      ],
      async (tx) => {
        const hit = await tx.findIdempotencyRecord(userId, endpoint, clientRequestId);
        if (hit) {
          if (hit.payloadHash !== hash) throw err.payloadMismatch();
          return hit.responseBody;
        }

        const zone = timezone ?? (await this.tzOf(userId, tx));
        const streak = await this.getOrCreate(userId, zone, tx);
        const now = new Date();
        const today = localDateOf(now, zone);

        // 断签日 D 起 7 个自然日 [D, D+6] 可补；不含今天（断食可能仍在进行）
        if (date >= today || date <= addDays(today, -MAKEUP_WINDOW_DAYS)) {
          throw err.makeupOutOfWindow();
        }
        if (streak.makeupCards.usedDates.includes(date)) throw err.makeupAlreadyUsed();
        if ((await this.qualifiedDates(userId, tx)).has(date)) {
          throw err.makeupAlreadyUsed();
        }
        if (streak.makeupCards.stock <= 0) throw err.makeupCardEmpty();

        streak.makeupCards.stock -= 1;
        streak.makeupCards.usedDates.push(date);
        streak.updatedAt = now;
        await tx.saveStreak(streak);
        const marker: FastingRecordEntity = {
          id: newId(),
          userId,
          attributionDate: date,
          plannedStartAt: now,
          plannedEndAt: now,
          actualStartAt: null,
          actualEndAt: null,
          extendedMinutes: 0,
          fastedMinutes: null,
          result: 'makeup',
          isQualified: true,
          eventLog: [{ at: now.toISOString(), event: 'makeup', detail: { clientRequestId } }],
          clientRequestId,
          version: 1,
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
        };
        await tx.saveFastingRecord(marker);

        const updated = await this.recompute(userId, tx, zone);
        const response = this.streakView(updated, zone);
        await tx.saveIdempotencyRecord({
          userId,
          clientRequestId,
          endpoint,
          payloadHash: hash,
          responseBody: response,
          createdAt: new Date(),
        });
        return response;
      },
    );
  }

  streakView(streak: StreakEntity, tz: string) {
    const cards = streak.makeupCards;
    const [y, m] = cards.month.split('-').map(Number);
    const expiresAt = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10); // 月末
    const today = localDateOf(new Date(), tz);
    const yesterday = addDays(today, -1);
    const recentlyBroken =
      streak.lastQualifiedDate !== null &&
      streak.lastQualifiedDate < yesterday &&
      cards.stock === 0;
    return {
      currentStreak: streak.currentStreak,
      longestStreak: streak.longestStreak,
      lastQualifiedDate: streak.lastQualifiedDate,
      makeupCards: {
        stock: cards.stock,
        grantsThisMonth: MONTHLY_GRANT,
        expiresAt,
        usableWindowDays: MAKEUP_WINDOW_DAYS,
        status: cards.stock > 0 ? 'available' : recentlyBroken ? 'broken' : 'empty',
      },
    };
  }
}
