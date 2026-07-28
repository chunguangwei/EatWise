import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore, FastingRecordEntity, StreakEntity } from '../common/store/data-store';
import { newId, payloadHash } from '../common/utils/id.util';
import { addDays, localDateOf, localMonthOf } from '../common/utils/time.util';

const MONTHLY_GRANT = 2; // 每月 1 日发放 2 张（D-12）
const STOCK_CAP = 2; // 库存上限 2 张，不累积（D-12）
const MAKEUP_WINDOW_DAYS = 7; // 仅可补最近 7 天内的断签日（D-12）
const MILESTONES = [3, 7, 30];

/**
 * Streak 与补签卡（D-12）：口径 = 断食打卡达标，服务端权威计算。
 */
@Injectable()
export class StreakService {
  constructor(private readonly store: DataStore) {}

  private tzOf(userId: string): string {
    return this.store.users.get(userId)?.timezone ?? 'Asia/Shanghai';
  }

  /** 读取（不存在则初始化），并执行月度 rollover：当月有效、月底清零、月初发 2 张（上限 2） */
  getOrCreate(userId: string, tz?: string): StreakEntity {
    const zone = tz ?? this.tzOf(userId);
    let streak = this.store.streaks.get(userId);
    if (!streak) {
      streak = {
        id: newId(),
        userId,
        currentStreak: 0,
        longestStreak: 0,
        lastQualifiedDate: null,
        milestones: {},
        makeupCards: { stock: MONTHLY_GRANT, month: localMonthOf(new Date(), zone), usedDates: [] },
        version: 1,
        updatedAt: new Date(),
      };
      this.store.streaks.set(userId, streak);
    }
    // 月度 rollover：进入新月 → 清零重发 2 张（发放时已有则不超上限）
    const currentMonth = localMonthOf(new Date(), zone);
    if (streak.makeupCards.month !== currentMonth) {
      streak.makeupCards = {
        stock: Math.min(STOCK_CAP, MONTHLY_GRANT),
        month: currentMonth,
        usedDates: [],
      };
      streak.updatedAt = new Date();
    }
    return streak;
  }

  /** 达标日期集合：断食达标（D-08）或补签日 */
  qualifiedDates(userId: string): Set<string> {
    const dates = new Set<string>();
    for (const r of this.store.fastingRecords.values()) {
      if (r.userId !== userId) continue;
      if (r.isQualified || r.result === 'makeup') dates.add(r.attributionDate);
    }
    return dates;
  }

  /** 由达标日重算 streak（中断 → 当前 streak 归零，D-12） */
  recompute(userId: string): StreakEntity {
    const streak = this.getOrCreate(userId);
    const tz = this.tzOf(userId);
    const dates = [...this.qualifiedDates(userId)].sort();
    const today = localDateOf(new Date(), tz);
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
        streak.milestones[String(m)] = new Date().toISOString();
      }
    }
    streak.version += 1;
    streak.updatedAt = new Date();
    return streak;
  }

  /** S2 使用补签卡（D-12 规则表，服务端强制执行） */
  makeUp(userId: string, clientRequestId: string, date: string) {
    const endpoint = 'streak/makeup';
    const hash = payloadHash({ date });
    const hit = this.store.idempotency.get(this.store.idemKey(userId, endpoint, clientRequestId));
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const streak = this.getOrCreate(userId);
    const tz = this.tzOf(userId);
    const today = localDateOf(new Date(), tz);

    // 可补范围：最近 7 个自然日内的断签日（不含今天，今天的断食可能还在进行）
    if (date >= today || date < addDays(today, -MAKEUP_WINDOW_DAYS)) {
      throw err.makeupOutOfWindow();
    }
    if (streak.makeupCards.usedDates.includes(date)) throw err.makeupAlreadyUsed();
    if (this.qualifiedDates(userId).has(date)) throw err.makeupAlreadyUsed(); // 〔假设〕已达标日无需补签
    if (streak.makeupCards.stock <= 0) throw err.makeupCardEmpty();

    streak.makeupCards.stock -= 1;
    streak.makeupCards.usedDates.push(date);
    // 〔假设〕补签在断食历史中留痕：生成 result=makeup 的标记记录（契约 §3.8）
    const now = new Date();
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
    };
    this.store.fastingRecords.set(marker.id, marker);

    const updated = this.recompute(userId);
    const response = this.streakView(updated, tz);
    this.store.idempotency.set(this.store.idemKey(userId, endpoint, clientRequestId), {
      userId,
      clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: new Date(),
    });
    return response;
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
