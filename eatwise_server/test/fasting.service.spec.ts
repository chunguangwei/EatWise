import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { newId } from '../src/common/utils/id.util';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { PutPlanDto } from '../src/fasting/fasting.dto';
import { computeWindow, FastingService, MAX_EXTEND_MINUTES } from '../src/fasting/fasting.service';
import { StreakService } from '../src/streak/streak.service';

const TZ = 'Asia/Shanghai';
const PLAN = { eatingWindowStart: '12:00', eatingWindowEnd: '20:00' }; // 16:8

describe('fasting：归属日（D-07）/ 容差（D-08）/ 延长（D-10）', () => {
  let store: DataStore;
  let fasting: FastingService;
  let userId: string;

  beforeEach(() => {
    store = new DataStore();
    const driver = new MemoryStoreDriver(store);
    fasting = new FastingService(driver, new ConfigService(), new StreakService(driver));
    userId = store.createUser({ phone: '+8613800138000', timezone: TZ }).id;
  });

  function makeRecord(overrides: Partial<FastingRecordEntity> = {}): FastingRecordEntity {
    const now = new Date();
    const record: FastingRecordEntity = {
      id: newId(),
      userId,
      attributionDate: '2026-07-27',
      plannedStartAt: new Date('2026-07-26T12:00:00.000Z'), // 昨日 20:00 本地
      plannedEndAt: new Date('2026-07-27T04:00:00.000Z'), // 今日 12:00 本地
      actualStartAt: new Date('2026-07-26T12:00:00.000Z'),
      actualEndAt: null,
      extendedMinutes: 0,
      fastedMinutes: null,
      result: 'on_track',
      isQualified: false,
      eventLog: [],
      clientRequestId: null,
      version: 1,
      createdAt: now,
      updatedAt: now,
      ...overrides,
    };
    store.fastingRecords.set(record.id, record);
    return record;
  }

  describe('归属日与窗口计算（D-07）', () => {
    it('上午（断食中）：窗口属于今天，归属日 = 今天', () => {
      const win = computeWindow(PLAN, TZ, new Date('2026-07-27T01:00:00.000Z')); // 09:00 本地
      expect(win.state).toBe('fasting');
      expect(win.eatingStartAt.toISOString()).toBe('2026-07-27T04:00:00.000Z'); // 12:00 本地
      expect(win.eatingEndAt.toISOString()).toBe('2026-07-27T12:00:00.000Z'); // 20:00 本地
    });

    it('进食窗口内：state = eating', () => {
      const win = computeWindow(PLAN, TZ, new Date('2026-07-27T06:00:00.000Z')); // 14:00 本地
      expect(win.state).toBe('eating');
    });

    it('跨午夜（晚上断食中）：归属日 = 明天（进食窗口所属自然日）', () => {
      const win = computeWindow(PLAN, TZ, new Date('2026-07-27T14:00:00.000Z')); // 22:00 本地
      expect(win.state).toBe('fasting');
      expect(win.eatingStartAt.toISOString()).toBe('2026-07-28T04:00:00.000Z');
    });

    it('getStatus 物化的 activeRecord 归属日由服务端计算', async () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T01:00:00.000Z'));
      try {
        const status = await fasting.getStatus(userId, TZ);
        expect(status.state).toBe('fasting');
        expect(status.activeRecord?.attributionDate).toBe('2026-07-27');
        expect(status.toleranceMinutes).toBe(15);
        expect(status.extendRemainingMinutes).toBe(240);
      } finally {
        jest.useRealTimers();
      }
    });
  });

  describe('达标判定与破窗容差（D-08，容差 15min）', () => {
    it('进食窗口按时开启 → completed，达标', async () => {
      const r = makeRecord();
      const res = (await fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      )) as {
        result: string;
        isQualified: boolean;
        fastedMinutes: number;
      };
      expect(res.result).toBe('completed');
      expect(res.isQualified).toBe(true);
      expect(res.fastedMinutes).toBe(16 * 60);
    });

    it('提前恰好 =15min → ended_early，仍达标（边界）', async () => {
      const r = makeRecord();
      const res = (await fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T03:45:00.000Z'),
      )) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('ended_early');
      expect(res.isQualified).toBe(true);
    });

    it('提前 >15min → broken，不达标（边界）', async () => {
      const r = makeRecord();
      const res = (await fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T03:44:00.000Z'),
      )) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('broken');
      expect(res.isQualified).toBe(false);
    });

    it('延长后最终时长 ≥ 计划 → completed', async () => {
      const r = makeRecord({
        extendedMinutes: 30,
        plannedEndAt: new Date('2026-07-27T04:30:00.000Z'),
      });
      const res = (await fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T04:30:00.000Z'),
      )) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('completed');
      expect(res.isQualified).toBe(true);
    });

    it('重复结束（同 clientRequestId）返回首次结果；新请求 → 409 FASTING_ALREADY_ENDED', async () => {
      const r = makeRecord();
      const clientRequestId = randomUUID();
      const first = await fasting.endFast(
        userId,
        clientRequestId,
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      );
      const replay = await fasting.endFast(
        userId,
        clientRequestId,
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      );
      expect(replay).toEqual(first);
      await expect(
        fasting.endFast(userId, randomUUID(), r.id, new Date('2026-07-27T04:00:00.000Z')),
      ).rejects.toThrow(
        expect.objectContaining({ code: 'FASTING_ALREADY_ENDED' }) as unknown as Error,
      );
    });
  });

  describe('延长（D-10：步进 30min，累计 ≤240min）', () => {
    it('步进非 30 的倍数 → VALIDATION_ERROR', async () => {
      const r = makeRecord();
      await expect(fasting.extend(userId, randomUUID(), r.id, 45)).rejects.toThrow(
        expect.objectContaining({ code: 'VALIDATION_ERROR' }) as unknown as Error,
      );
    });

    it('延长 30min：plannedEndAt 后移，剩余额度 210', async () => {
      const r = makeRecord();
      const res = (await fasting.extend(userId, randomUUID(), r.id, 30)) as {
        plannedEndAt: string;
        extendedMinutes: number;
        extendRemainingMinutes: number;
      };
      expect(res.plannedEndAt).toBe('2026-07-27T04:30:00.000Z');
      expect(res.extendedMinutes).toBe(30);
      expect(res.extendRemainingMinutes).toBe(210);
    });

    it('累计达 240 后再延长 → 400 FASTING_EXTEND_LIMIT（上限 4h）', async () => {
      const r = makeRecord();
      for (let i = 0; i < MAX_EXTEND_MINUTES / 30; i++) {
        await fasting.extend(userId, randomUUID(), r.id, 30);
      }
      expect(store.fastingRecords.get(r.id)!.extendedMinutes).toBe(240);
      await expect(fasting.extend(userId, randomUUID(), r.id, 30)).rejects.toThrow(
        expect.objectContaining({
          code: 'FASTING_EXTEND_LIMIT',
          details: { extendRemainingMinutes: 0 },
        }) as unknown as Error,
      );
    });

    it('单次延长超过剩余额度 → FASTING_EXTEND_LIMIT，剩余额度见 details', async () => {
      const r = makeRecord({ extendedMinutes: 210 });
      await expect(fasting.extend(userId, randomUUID(), r.id, 60)).rejects.toThrow(
        expect.objectContaining({
          code: 'FASTING_EXTEND_LIMIT',
          details: { extendRemainingMinutes: 30 },
        }) as unknown as Error,
      );
    });
  });

  describe('延长后状态保持（plannedEndAt 后移不丢记录、不重复建档）', () => {
    it('延长后再次查询（断食窗口内）：返回同一记录，不重复建档', async () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T01:00:00.000Z')); // 09:00 本地，断食中
      try {
        const s1 = await fasting.getStatus(userId, TZ);
        const recordId = s1.activeRecord!.id;
        await fasting.extend(userId, randomUUID(), recordId, 30); // plannedEndAt 后移 30min
        const count = store.fastingRecords.size;
        const s2 = await fasting.getStatus(userId, TZ);
        expect(s2.state).toBe('fasting');
        expect(s2.activeRecord?.id).toBe(recordId);
        expect(s2.activeRecord?.extendedMinutes).toBe(30);
        expect(store.fastingRecords.size).toBe(count); // 无重复建档
      } finally {
        jest.useRealTimers();
      }
    });

    it('延长覆盖名义进食窗口：state 仍为 fasting，activeRecord 保留；延长窗口过后果进食', async () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T01:00:00.000Z'));
      try {
        const s1 = await fasting.getStatus(userId, TZ);
        const recordId = s1.activeRecord!.id;
        await fasting.extend(userId, randomUUID(), recordId, 30); // plannedEndAt → 12:30 本地

        jest.setSystemTime(new Date('2026-07-27T04:15:00.000Z')); // 12:15 本地：名义进食窗口
        const s2 = await fasting.getStatus(userId, TZ);
        expect(s2.state).toBe('fasting'); // 记录优先于 plan 窗口：断食状态不消失
        expect(s2.activeRecord?.id).toBe(recordId);

        jest.setSystemTime(new Date('2026-07-27T05:00:00.000Z')); // 13:00 本地：延长窗口已过
        const s3 = await fasting.getStatus(userId, TZ);
        expect(s3.state).toBe('eating');
        expect(s3.activeRecord?.id).toBe(recordId); // 未结束的记录仍回显（不重复建档）
        expect(store.fastingRecords.size).toBe(1);
      } finally {
        jest.useRealTimers();
      }
    });

    it('ghost 自动结算：过期 on_track（客户端漏报 F2）→ 下次 F1 按自然结束 completed，新窗口正常建档', async () => {
      // 生产走查根因钉死：旧版客户端（X-Timezone 误报 UTC）自动对账链路断了 F2 上报时，
      // on_track 行永久劫持 findOrCreateActiveRecord，后续窗口不再建档、streak 永不自愈。
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T01:00:00.000Z')); // 09:00 断食中
      try {
        const s1 = await fasting.getStatus(userId, TZ);
        const ghostId = s1.activeRecord!.id;

        // 窗口结束（12:00 本地）后客户端始终没报 F2 → ghost 过期
        jest.setSystemTime(new Date('2026-07-27T05:00:00.000Z')); // 13:00 进食中
        const s2 = await fasting.getStatus(userId, TZ);
        expect(s2.state).toBe('eating');
        expect(s2.activeRecord?.id).toBe(ghostId); // 回显刚结算的记录
        expect(s2.activeRecord?.result).toBe('completed'); // 无中断证据 = 自然结束
        expect(s2.activeRecord?.fastedMinutes).toBe(16 * 60);
        expect(s2.streak.currentStreak).toBe(1); // 达标入 streak（原 bug：永不达标）

        // 下一断食窗口正常建档（ghost 不再劫持）
        jest.setSystemTime(new Date('2026-07-27T14:00:00.000Z')); // 22:00 断食中
        const s3 = await fasting.getStatus(userId, TZ);
        expect(s3.activeRecord?.id).not.toBe(ghostId);
        expect(store.fastingRecords.size).toBe(2);
      } finally {
        jest.useRealTimers();
      }
    });
  });

  describe('方案窗口与 planType 一致性校验（自选进食窗口）', () => {
    async function errorsFor(body: Record<string, unknown>) {
      return validate(plainToInstance(PutPlanDto, body), { whitelist: true });
    }

    it('16:8 配 10h 窗口（09:00–19:00）→ 校验失败', async () => {
      const errors = await errorsFor({
        clientRequestId: randomUUID(),
        planType: '16:8',
        eatingWindow: { start: '09:00', end: '19:00' },
      });
      expect(errors.length).toBeGreaterThan(0);
    });

    it('16:8 配 8h 窗口（09:00–17:00）→ 通过', async () => {
      const errors = await errorsFor({
        clientRequestId: randomUUID(),
        planType: '16:8',
        eatingWindow: { start: '09:00', end: '17:00' },
      });
      expect(errors).toEqual([]);
    });

    it('跨午夜 22:00–06:00 配 16:8 → 通过；20:00–06:00（10h）配 16:8 → 失败、配 14:10 → 通过', async () => {
      expect(
        await errorsFor({
          clientRequestId: randomUUID(),
          planType: '16:8',
          eatingWindow: { start: '22:00', end: '06:00' },
        }),
      ).toEqual([]);
      expect(
        (
          await errorsFor({
            clientRequestId: randomUUID(),
            planType: '16:8',
            eatingWindow: { start: '20:00', end: '06:00' },
          })
        ).length,
      ).toBeGreaterThan(0); // (360−1200+1440)%1440 = 600 ≠ 480
      expect(
        await errorsFor({
          clientRequestId: randomUUID(),
          planType: '14:10',
          eatingWindow: { start: '20:00', end: '06:00' },
        }),
      ).toEqual([]);
    });

    it('18:6 配 6h 跨午夜（21:00–03:00）通过；14:10 配 08:00–17:00（9h）失败', async () => {
      expect(
        await errorsFor({
          clientRequestId: randomUUID(),
          planType: '18:6',
          eatingWindow: { start: '21:00', end: '03:00' },
        }),
      ).toEqual([]);
      const bad = await errorsFor({
        clientRequestId: randomUUID(),
        planType: '14:10',
        eatingWindow: { start: '08:00', end: '17:00' },
      });
      expect(bad.length).toBeGreaterThan(0);
    });

    it('eatingWindow 缺失 / planType 非法 → 各自字段级报错（不 500）', async () => {
      expect(
        (await errorsFor({ clientRequestId: randomUUID(), planType: '16:8' })).length,
      ).toBeGreaterThan(0);
      expect(
        (
          await errorsFor({
            clientRequestId: randomUUID(),
            planType: '20:4',
            eatingWindow: { start: '09:00', end: '17:00' },
          })
        ).length,
      ).toBeGreaterThan(0);
    });
  });

  describe('跨午夜进食窗口（20:00–06:00，16:8）', () => {
    const CROSS = { eatingWindowStart: '20:00', eatingWindowEnd: '06:00' };

    it('凌晨 02:00：eating，窗口锚定昨天（起点=昨日 20:00）', () => {
      const win = computeWindow(CROSS, TZ, new Date('2026-07-26T18:00:00.000Z')); // 27 日 02:00 本地
      expect(win.state).toBe('eating');
      expect(win.eatingStartAt.toISOString()).toBe('2026-07-26T12:00:00.000Z'); // 26 日 20:00 本地
      expect(win.eatingEndAt.toISOString()).toBe('2026-07-26T22:00:00.000Z'); // 27 日 06:00 本地
    });

    it('22:00（窗口起点后）：eating，止点落次日 06:00', () => {
      const win = computeWindow(CROSS, TZ, new Date('2026-07-27T14:00:00.000Z')); // 22:00 本地
      expect(win.state).toBe('eating');
      expect(win.eatingStartAt.toISOString()).toBe('2026-07-27T12:00:00.000Z');
      expect(win.eatingEndAt.toISOString()).toBe('2026-07-27T22:00:00.000Z'); // 28 日 06:00 本地
    });

    it('10:00（断食中）：fasting，下一窗口 = 今日 20:00 起', () => {
      const win = computeWindow(CROSS, TZ, new Date('2026-07-27T02:00:00.000Z')); // 10:00 本地
      expect(win.state).toBe('fasting');
      expect(win.eatingStartAt.toISOString()).toBe('2026-07-27T12:00:00.000Z');
    });

    it('getStatus 建档：归属日 = 今日（窗口起点日），断食起点 = 今日 06:00（窗口止点）', async () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T02:00:00.000Z')); // 10:00 本地断食中
      try {
        await fasting.putCurrentPlan(userId, TZ, '16:8', '20:00', '06:00');
        const status = await fasting.getStatus(userId, TZ);
        expect(status.state).toBe('fasting');
        expect(status.activeRecord?.attributionDate).toBe('2026-07-27');
        expect(status.activeRecord?.plannedStartAt).toBe('2026-07-26T22:00:00.000Z'); // 今日 06:00 本地
        expect(status.activeRecord?.plannedEndAt).toBe('2026-07-27T12:00:00.000Z'); // 今日 20:00 本地
      } finally {
        jest.useRealTimers();
      }
    });

    it('凌晨进食中 getStatus：eating 不建档；延长覆盖名义进窗后状态保持', async () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T02:00:00.000Z'));
      try {
        await fasting.putCurrentPlan(userId, TZ, '16:8', '20:00', '06:00');
        jest.setSystemTime(new Date('2026-07-26T18:00:00.000Z')); // 27 日 02:00 本地：进食中
        const s0 = await fasting.getStatus(userId, TZ);
        expect(s0.state).toBe('eating');
        expect(s0.window.eatingStartAt).toBe('2026-07-26T12:00:00.000Z'); // 周期起点 = 昨日 20:00
        expect(store.fastingRecords.size).toBe(0); // 进食态不建档

        jest.setSystemTime(new Date('2026-07-27T02:00:00.000Z')); // 回到 10:00 本地：断食中
        const s1 = await fasting.getStatus(userId, TZ);
        const recordId = s1.activeRecord!.id;
        await fasting.extend(userId, randomUUID(), recordId, 30); // plannedEndAt → 20:30 本地
        jest.setSystemTime(new Date('2026-07-27T12:15:00.000Z')); // 20:15 本地：名义已进窗
        const s2 = await fasting.getStatus(userId, TZ);
        expect(s2.state).toBe('fasting'); // 延长覆盖窗口：状态不消失
        expect(s2.activeRecord?.id).toBe(recordId);
        expect(store.fastingRecords.size).toBe(1); // 无重复建档
      } finally {
        jest.useRealTimers();
      }
    });
  });
  describe('方案生效语义：首个立即生效 / 改动次日（D-06 修订）', () => {
    beforeEach(() => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T02:00:00.000Z')); // 本地 2026-07-27 10:00
    });
    afterEach(() => jest.useRealTimers());

    it('首个方案：effectiveDate=今日、status=current，getCurrentPlan 不再是 16:8 兜底', async () => {
      const res = await fasting.putCurrentPlan(userId, TZ, '18:6', '21:00', '03:00');
      expect(res.current.status).toBe('current');
      expect(res.current.effectiveDate).toBe('2026-07-27');
      expect(res.current.planType).toBe('18:6');
      const current = await fasting.getCurrentPlan(userId, TZ);
      expect(current.id).not.toBe('default');
      expect(current.eatingWindowStart).toBe('21:00');
    });

    it('已有方案再改：pending 次日生效，current 不变', async () => {
      const first = await fasting.putCurrentPlan(userId, TZ, '16:8', '09:00', '17:00');
      const res = await fasting.putCurrentPlan(userId, TZ, '14:10', '08:00', '18:00');
      expect(res.pending.status).toBe('pending');
      expect(res.pending.effectiveDate).toBe('2026-07-28');
      expect(res.current.id).toBe(first.current.id);
      expect(res.current.planType).toBe('16:8');
      // 当前生效口径仍是旧方案（计时不提前切换）
      const current = await fasting.getCurrentPlan(userId, TZ);
      expect(current.planType).toBe('16:8');
    });

    it('pending 再次 PUT：整体替换（LWW），仍次日生效', async () => {
      await fasting.putCurrentPlan(userId, TZ, '16:8', '09:00', '17:00');
      const p2 = await fasting.putCurrentPlan(userId, TZ, '14:10', '08:00', '18:00');
      const p3 = await fasting.putCurrentPlan(userId, TZ, '18:6', '21:00', '03:00');
      expect(p3.pending.id).toBe(p2.pending.id);
      expect(p3.pending.planType).toBe('18:6');
      expect(p3.pending.effectiveDate).toBe('2026-07-28');
      expect(store.fastingPlans.size).toBe(2); // current + 单条 pending
    });
  });
});
