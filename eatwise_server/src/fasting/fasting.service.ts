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

export interface FastingWindow {
  state: 'fasting' | 'eating';
  eatingStartAt: Date;
  eatingEndAt: Date;
}

/** 当前周期进食窗口（UTC 边界）。进食窗口同一天内 start < end（〔假设〕不支持跨午夜窗口） */
export function computeWindow(
  plan: { eatingWindowStart: string; eatingWindowEnd: string },
  tz: string,
  now: Date,
): FastingWindow {
  const today = localDateOf(now, tz);
  const todayStart = zonedTimeToUtc(today, plan.eatingWindowStart, tz);
  const todayEnd = zonedTimeToUtc(today, plan.eatingWindowEnd, tz);
  if (now.getTime() < todayStart.getTime()) {
    return {
      state: 'fasting',
      eatingStartAt: todayStart,
      eatingEndAt: todayEnd,
    };
  }
  if (now.getTime() < todayEnd.getTime()) {
    return { state: 'eating', eatingStartAt: todayStart, eatingEndAt: todayEnd };
  }
  const tomorrow = addDays(today, 1);
  return {
    state: 'fasting',
    eatingStartAt: zonedTimeToUtc(tomorrow, plan.eatingWindowStart, tz),
    eatingEndAt: zonedTimeToUtc(tomorrow, plan.eatingWindowEnd, tz),
  };
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

  /** P4 一键启动/更换方案：次日 0 点本地生效（D-06），已有 pending 整体替换（LWW） */
  async putCurrentPlan(userId: string, tz: string, planType: string, start: string, end: string) {
    const plans = await this.driver.listFastingPlansByUser(userId);
    const effectiveDate = addDays(localDateOf(new Date(), tz), 1);
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
        status: 'pending',
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
    // 进行中的记录优先于 plan 窗口：延长会后移 plannedEndAt，脱离窗口精确匹配口径
    let activeRecord: FastingRecordEntity | null =
      await this.driver.findOngoingFastingRecord(userId);
    if (!activeRecord) {
      if (win.state === 'fasting') {
        activeRecord = await this.findOrCreateActiveRecord(userId, plan, win, tz, now);
      } else {
        activeRecord = await this.driver.findFastingRecordByPlannedEnd(userId, win.eatingStartAt);
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
    // 断食开始 = 上一进食窗口结束
    const startDate = addDays(localDateOf(plannedEndAt, tz), -1);
    const plannedStartAt = zonedTimeToUtc(startDate, plan.eatingWindowEnd, tz);
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
    };
    await this.driver.saveFastingRecord(record);
    return record;
  }

  /** F2 手动结束断食：幂等 + 状态机 + D-08 达标判定 */
  async endFast(userId: string, clientRequestId: string, recordId: string, endedAt: Date) {
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

    // TODO 〔假设〕契约要求 endedAt 与服务端收到时间漂移 >5min 时采信服务端时间；骨架阶段采信客户端上报值
    const actualEnd = endedAt;
    const earlyByMs = record.plannedEndAt.getTime() - actualEnd.getTime();
    const toleranceMs = this.toleranceMinutes * 60 * 1000;

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
