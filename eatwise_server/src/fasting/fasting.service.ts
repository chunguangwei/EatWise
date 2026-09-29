import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { err } from '../common/errors/business.exception';
import { FastingPlanEntity, FastingRecordEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { addDays, localDateOf, zonedTimeToUtc } from '../common/utils/time.util';
import { StreakService } from '../streak/streak.service';

export const MAX_EXTEND_MINUTES = 240; // D-10：累计 ≤4h
export const EXTEND_STEP_MINUTES = 30; // D-10：步进 30min

/** F4 历史查询范围上限（天）：展示兜底用途，防全表拖取 */
export const MAX_RECORDS_RANGE_DAYS = 62;

export interface FastingWindow {
  state: 'fasting' | 'eating';
  eatingStartAt: Date;
  eatingEndAt: Date;
}

/** 锚定日（窗口起点所属本地自然日）的进食窗口 UTC 边界；end ≤ start 视为跨午夜，止点落次日 */
function windowFor(
  anchorDate: string,
  plan: { eatingWindowStart: string; eatingWindowEnd: string },
  tz: string,
): { eatingStartAt: Date; eatingEndAt: Date } {
  const crossMidnight = plan.eatingWindowEnd <= plan.eatingWindowStart;
  return {
    eatingStartAt: zonedTimeToUtc(anchorDate, plan.eatingWindowStart, tz),
    eatingEndAt: zonedTimeToUtc(
      crossMidnight ? addDays(anchorDate, 1) : anchorDate,
      plan.eatingWindowEnd,
      tz,
    ),
  };
}

/**
 * 当前周期进食窗口（UTC 边界）。支持跨午夜窗口（如 20:00–06:00）：
 * 凌晨处于「昨日窗口」内（now < 今日 start 但 < 昨日窗口的止点）→ eating；
 * 归属日（D-07）= 当前周期窗口**起点**所在本地自然日（凌晨 02:00 的周期起点是昨天）。
 */
export function computeWindow(
  plan: { eatingWindowStart: string; eatingWindowEnd: string },
  tz: string,
  now: Date,
): FastingWindow {
  const today = localDateOf(now, tz);
  const t = now.getTime();
  const cur = windowFor(today, plan, tz);
  if (t >= cur.eatingStartAt.getTime()) {
    if (t < cur.eatingEndAt.getTime()) return { state: 'eating', ...cur };
    return { state: 'fasting', ...windowFor(addDays(today, 1), plan, tz) };
  }
  const prev = windowFor(addDays(today, -1), plan, tz);
  if (t < prev.eatingEndAt.getTime()) return { state: 'eating', ...prev };
  return { state: 'fasting', ...cur };
}

@Injectable()
export class FastingService {
  constructor(
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
    private readonly config: ConfigService,
    private readonly streak: StreakService,
  ) {}

  private get toleranceMinutes(): number {
    // D-08：容差 15 分钟走服务端配置，可热调
    return Number(this.config.get('FASTING_TOLERANCE_MINUTES', 15));
  }

  /** 当前方案（无则 16:8 12:00–20:00 兜底，D-03）；到达 effectiveDate 的 pending 翻转为 current（D-06） */
  async getCurrentPlan(userId: string, tz: string): Promise<FastingPlanEntity> {
    const plans = await this.driver.listFastingPlansByUser(userId);
    const today = localDateOf(new Date(), tz);
    for (const p of plans.filter((p) => p.status === 'pending' && p.effectiveDate <= today)) {
      const current = plans.find((c) => c.status === 'current');
      if (current) {
        current.status = 'expired';
        await this.driver.saveFastingPlan(current);
      }
      p.status = 'current';
      await this.driver.saveFastingPlan(p);
    }
    const current = plans.find((p) => p.status === 'current');
    if (current) return current;
    return {
      id: 'default',
      userId,
      planType: '16:8',
      eatingWindowStart: '12:00',
      eatingWindowEnd: '20:00',
      effectiveDate: today,
      status: 'current',
      clientRequestId: null,
      version: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
  }

  /**
   * P4 一键启动/更换方案：已有 current/pending 方案时次日 0 点本地生效（D-06），
   * 已有 pending 整体替换（LWW）；用户首个方案（库中无任何 current/pending，
   * 16:8 兜底 D-03 是虚拟值不算）立即生效：effectiveDate=今日本地日、status=current。
   */
  async putCurrentPlan(userId: string, tz: string, planType: string, start: string, end: string) {
    const plans = await this.driver.listFastingPlansByUser(userId);
    const hasPrior = plans.some((p) => p.status === 'current' || p.status === 'pending');
    const today = localDateOf(new Date(), tz);
    const effectiveDate = addDays(today, hasPrior ? 1 : 0);
    let pending = plans.find((p) => p.status === 'pending');
    if (pending) {
      pending.planType = planType;
      pending.eatingWindowStart = start;
      pending.eatingWindowEnd = end;
      pending.effectiveDate = effectiveDate;
      pending.version += 1;
      pending.updatedAt = new Date();
    } else {
      pending = {
        id: newId(),
        userId,
        planType,
        eatingWindowStart: start,
        eatingWindowEnd: end,
        effectiveDate,
        status: hasPrior ? 'pending' : 'current',
        clientRequestId: null,
        version: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    }
    await this.driver.saveFastingPlan(pending);
    const current = await this.getCurrentPlan(userId, tz);
    return { current: this.planView(current), pending: this.planView(pending) };
  }

  /** F1 当前断食状态（首页计时环数据源） */
  async getStatus(userId: string, tz: string) {
    const now = new Date();
    const plan = await this.getCurrentPlan(userId, tz);
    const win = computeWindow(plan, tz, now);
    // 进行中的记录优先于 plan 窗口：延长会后移 plannedEndAt，脱离窗口精确匹配口径。
    // 过期 on_track（客户端杀进程漏报 F2 的 ghost）：无提前结束上报=无中断证据，
    // 按计划终点自动结算为自然结束（completed）——否则 ghost 永久劫持后续窗口的
    // 物化（findOrCreate 命中 ongoing 直接返回）且 streak 永不自愈（真机走查）。
    let activeRecord: FastingRecordEntity | null = null;
    let settled: FastingRecordEntity | null = null;
    const ongoing = await this.driver.findOngoingFastingRecord(userId);
    if (ongoing) {
      if (ongoing.plannedEndAt.getTime() > now.getTime()) {
        activeRecord = ongoing;
      } else {
        settled = await this.autoCloseExpired(ongoing, now);
      }
    }
    if (!activeRecord) {
      if (win.state === 'fasting') {
        activeRecord = await this.findOrCreateActiveRecord(userId, plan, win, tz, now);
      } else {
        // 延长后 plannedEndAt 偏离口径时回显刚自动结算的记录（不重复建档）
        activeRecord =
          (await this.driver.findFastingRecordByPlannedEnd(userId, win.eatingStartAt)) ?? settled;
      }
    }
    // 延长覆盖名义进食窗口（on_track 且 plannedEndAt>now）→ 仍在断食，状态不消失
    const recordActive =
      activeRecord?.result === 'on_track' && activeRecord.plannedEndAt.getTime() > now.getTime();
    const state = win.state === 'eating' && recordActive ? 'fasting' : win.state;
    const streak = await this.streak.getOrCreate(userId, tz);
    return {
      state,
      plan: {
        planType: plan.planType,
        eatingWindow: { start: plan.eatingWindowStart, end: plan.eatingWindowEnd },
      },
      window: {
        eatingStartAt: win.eatingStartAt.toISOString(),
        eatingEndAt: win.eatingEndAt.toISOString(),
      },
      activeRecord: activeRecord ? this.recordView(activeRecord) : null,
      toleranceMinutes: this.toleranceMinutes,
      extendRemainingMinutes: activeRecord
        ? MAX_EXTEND_MINUTES - activeRecord.extendedMinutes
        : MAX_EXTEND_MINUTES,
      streak: { currentStreak: streak.currentStreak },
    };
  }

  /** ghost 自动结算：completed 达标（口径=到点自然结束；手动中断由客户端 F2 实时上报） */
  private async autoCloseExpired(record: FastingRecordEntity, now: Date) {
    record.result = 'completed';
    record.isQualified = true;
    record.actualEndAt = record.plannedEndAt;
    record.fastedMinutes = Math.max(
      0,
      Math.round(
        (record.plannedEndAt.getTime() -
          (record.actualStartAt ?? record.plannedStartAt).getTime()) /
          60000,
      ),
    );
    record.version += 1;
    record.updatedAt = now;
    record.eventLog.push({
      at: now.toISOString(),
      event: 'auto_closed',
      detail: { result: record.result, isQualified: record.isQualified },
    });
    await this.driver.saveFastingRecord(record);
    await this.streak.recompute(record.userId);
    return record;
  }

  /**
   * F4 断食历史查询（只读，数据页近 7 日趋势展示兜底下行——客户端 fastingRecord
   * 无 /sync 通道，重装后本地历史全丢，经本接口按需回填）。
   * from/to 为归属日（yyyy-MM-dd，D-07 冻结字段）闭区间，字符串比较即日期序；
   * 范围上限 [MAX_RECORDS_RANGE_DAYS] 天防全表拖取。
   */
  async listRecords(userId: string, from: string, to: string) {
    const dateRe = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRe.test(from) || !dateRe.test(to) || from > to) {
      throw err.validation({ from: 'invalid date range (yyyy-MM-dd, from <= to)' });
    }
    if (addDays(from, MAX_RECORDS_RANGE_DAYS) < to) {
      throw err.validation({ to: `range must be <= ${MAX_RECORDS_RANGE_DAYS} days` });
    }
    const all = await this.driver.listFastingRecordsByUser(userId);
    return all
      .filter((r) => !r.deletedAt && r.attributionDate >= from && r.attributionDate <= to)
      .sort((a, b) => a.attributionDate.localeCompare(b.attributionDate))
      .map((r) => this.recordView(r));
  }

  /** 进行中的断食记录 find-or-create（〔假设〕随首次状态查询物化，归属日服务端算，D-07） */
  private async findOrCreateActiveRecord(
    userId: string,
    plan: FastingPlanEntity,
    win: FastingWindow,
    tz: string,
    now: Date,
  ): Promise<FastingRecordEntity> {
    // on_track 记录去重：延长后 plannedEndAt 已偏离窗口，先按进行中记录命中
    const ongoing = await this.driver.findOngoingFastingRecord(userId);
    if (ongoing) return ongoing;
    const plannedEndAt = win.eatingStartAt;
    const existing = await this.driver.findFastingRecordByPlannedEnd(userId, plannedEndAt);
    if (existing) return existing;
    // 断食开始 = 上一周期进食窗口的止点：起点日为归属日前一日的窗口（跨午夜窗口止点落次日）
    const prevWindow = windowFor(addDays(localDateOf(plannedEndAt, tz), -1), plan, tz);
    const plannedStartAt = prevWindow.eatingEndAt;
    const record: FastingRecordEntity = {
      id: newId(),
      userId,
      attributionDate: localDateOf(plannedEndAt, tz), // 归属日 = 进食窗口所属自然日（D-07）
      plannedStartAt,
      plannedEndAt,
      actualStartAt: plannedStartAt, // 〔假设〕无手动开始时按计划开始计
      actualEndAt: null,
      extendedMinutes: 0,
      fastedMinutes: null,
      result: 'on_track',
      isQualified: false,
      eventLog: [{ at: now.toISOString(), event: 'started' }],
      clientRequestId: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    await this.driver.saveFastingRecord(record);
    return record;
  }

  /** F2 手动结束断食：幂等 + 状态机 + D-08 达标判定 + B2 窗口签名防御 */
  async endFast(
    userId: string,
    clientRequestId: string,
    recordId: string,
    endedAt: Date,
    opts: { plannedStartAt?: Date | null; plannedEndAt?: Date | null } = {},
  ) {
    const endpoint = 'fasting/end';
    const hash = payloadHash({ recordId, endedAt });
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, clientRequestId);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const record = await this.driver.findFastingRecordById(recordId);
    if (!record || record.userId !== userId) throw err.notFound();
    if (record.result !== 'on_track') throw err.fastingAlreadyEnded();

    // B2 窗口签名防御（v1.13.28）：客户端带上本地周期计划锚点时，与服务端
    // 记录窗口不一致（>60s 容差）= 多端方案分叉互踩（分叉端按各自本地窗口
    // 结束周期，服务端按另一窗口判定→系统性误判 broken）。明确拒绝且
    // 不动记录，客户端吃 409 后触发方案下行收敛。缺签名（旧客户端）跳过。
    if (opts.plannedStartAt && opts.plannedEndAt) {
      const skewMs = 60 * 1000;
      if (
        Math.abs(opts.plannedStartAt.getTime() - record.plannedStartAt.getTime()) > skewMs ||
        Math.abs(opts.plannedEndAt.getTime() - record.plannedEndAt.getTime()) > skewMs
      ) {
        throw err.fastingWindowMismatch();
      }
    }

    // 归属防御（v1.13.27）：endedAt 落在本记录窗口 [实际开始−容差, 计划结束+容差]
    // 之外 = 上报归属错误（旧周期 endedAt 错挂当前 recordId，客户端 v1.13.27
    // 前 _reportAndRefresh 缺陷可制造）——拒绝结算，绝不把当前 on_track 记录
    // 结掉（wcg 四连 broken 根因之二）。幂等记录不落：重放必然同样拒绝。
    const toleranceMs = this.toleranceMinutes * 60 * 1000;
    const windowStartMs = (record.actualStartAt ?? record.plannedStartAt).getTime() - toleranceMs;
    const windowEndMs = record.plannedEndAt.getTime() + toleranceMs;
    if (endedAt.getTime() < windowStartMs || endedAt.getTime() > windowEndMs) {
      throw err.fastingEndOutOfWindow();
    }

    // TODO 〔假设〕契约要求 endedAt 与服务端收到时间漂移 >5min 时采信服务端时间；骨架阶段采信客户端上报值
    const actualEnd = endedAt;
    const earlyByMs = record.plannedEndAt.getTime() - actualEnd.getTime();

    if (earlyByMs <= 0) {
      record.result = 'completed';
      record.isQualified = true;
    } else if (earlyByMs <= toleranceMs) {
      record.result = 'ended_early';
      record.isQualified = true;
    } else {
      record.result = 'broken';
      record.isQualified = false;
    }
    record.actualEndAt = actualEnd;
    record.fastedMinutes = Math.max(
      0,
      Math.round(
        (actualEnd.getTime() - (record.actualStartAt ?? record.plannedStartAt).getTime()) / 60000,
      ),
    );
    record.version += 1;
    record.updatedAt = new Date();
    record.eventLog.push({
      at: new Date().toISOString(),
      event: 'ended',
      detail: { result: record.result, isQualified: record.isQualified },
    });
    await this.driver.saveFastingRecord(record);

    await this.streak.recompute(userId);
    const response = this.recordView(record);
    await this.driver.saveIdempotencyRecord({
      userId,
      clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: new Date(),
    });
    return response;
  }

  /** F3 延长：步进 30min、累计 ≤240min（D-10），进食窗口后移不压缩 */
  async extend(userId: string, clientRequestId: string, recordId: string, extendMinutes: number) {
    const endpoint = 'fasting/extend';
    const hash = payloadHash({ recordId, extendMinutes });
    const hit = await this.driver.findIdempotencyRecord(userId, endpoint, clientRequestId);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    const record = await this.driver.findFastingRecordById(recordId);
    if (!record || record.userId !== userId) throw err.notFound();
    if (record.result !== 'on_track') throw err.fastingAlreadyEnded();
    if (extendMinutes % EXTEND_STEP_MINUTES !== 0) {
      throw err.validation({ extendMinutes: `must be a multiple of ${EXTEND_STEP_MINUTES}` });
    }
    const remaining = MAX_EXTEND_MINUTES - record.extendedMinutes;
    if (extendMinutes > remaining) throw err.fastingExtendLimit(remaining);

    record.extendedMinutes += extendMinutes;
    record.plannedEndAt = new Date(record.plannedEndAt.getTime() + extendMinutes * 60000);
    record.version += 1;
    record.updatedAt = new Date();
    record.eventLog.push({
      at: new Date().toISOString(),
      event: 'extended',
      detail: { extendMinutes, extendedMinutes: record.extendedMinutes },
    });
    await this.driver.saveFastingRecord(record);

    const response = {
      ...this.recordView(record),
      extendRemainingMinutes: MAX_EXTEND_MINUTES - record.extendedMinutes,
    };
    await this.driver.saveIdempotencyRecord({
      userId,
      clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: new Date(),
    });
    return response;
  }

  private planView(p: FastingPlanEntity) {
    return {
      id: p.id,
      planType: p.planType,
      eatingWindow: { start: p.eatingWindowStart, end: p.eatingWindowEnd },
      effectiveDate: p.effectiveDate,
      status: p.status,
    };
  }

  private recordView(r: FastingRecordEntity) {
    return {
      id: r.id,
      attributionDate: r.attributionDate,
      plannedStartAt: r.plannedStartAt.toISOString(),
      plannedEndAt: r.plannedEndAt.toISOString(),
      actualStartAt: r.actualStartAt?.toISOString() ?? null,
      actualEndAt: r.actualEndAt?.toISOString() ?? null,
      extendedMinutes: r.extendedMinutes,
      fastedMinutes: r.fastedMinutes,
      result: r.result,
      isQualified: r.isQualified,
      version: r.version,
    };
  }
}
