import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { newId } from '../src/common/utils/id.util';
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
    fasting = new FastingService(store, new ConfigService(), new StreakService(store));
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

    it('getStatus 物化的 activeRecord 归属日由服务端计算', () => {
      jest.useFakeTimers().setSystemTime(new Date('2026-07-27T01:00:00.000Z'));
      try {
        const status = fasting.getStatus(userId, TZ);
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
    it('进食窗口按时开启 → completed，达标', () => {
      const r = makeRecord();
      const res = fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      ) as {
        result: string;
        isQualified: boolean;
        fastedMinutes: number;
      };
      expect(res.result).toBe('completed');
      expect(res.isQualified).toBe(true);
      expect(res.fastedMinutes).toBe(16 * 60);
    });

    it('提前恰好 =15min → ended_early，仍达标（边界）', () => {
      const r = makeRecord();
      const res = fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T03:45:00.000Z'),
      ) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('ended_early');
      expect(res.isQualified).toBe(true);
    });

    it('提前 >15min → broken，不达标（边界）', () => {
      const r = makeRecord();
      const res = fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T03:44:00.000Z'),
      ) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('broken');
      expect(res.isQualified).toBe(false);
    });

    it('延长后最终时长 ≥ 计划 → completed', () => {
      const r = makeRecord({
        extendedMinutes: 30,
        plannedEndAt: new Date('2026-07-27T04:30:00.000Z'),
      });
      const res = fasting.endFast(
        userId,
        randomUUID(),
        r.id,
        new Date('2026-07-27T04:30:00.000Z'),
      ) as {
        result: string;
        isQualified: boolean;
      };
      expect(res.result).toBe('completed');
      expect(res.isQualified).toBe(true);
    });

    it('重复结束（同 clientRequestId）返回首次结果；新请求 → 409 FASTING_ALREADY_ENDED', () => {
      const r = makeRecord();
      const clientRequestId = randomUUID();
      const first = fasting.endFast(
        userId,
        clientRequestId,
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      );
      const replay = fasting.endFast(
        userId,
        clientRequestId,
        r.id,
        new Date('2026-07-27T04:00:00.000Z'),
      );
      expect(replay).toEqual(first);
      expect(() =>
        fasting.endFast(userId, randomUUID(), r.id, new Date('2026-07-27T04:00:00.000Z')),
      ).toThrow(expect.objectContaining({ code: 'FASTING_ALREADY_ENDED' }) as unknown as Error);
    });
  });

  describe('延长（D-10：步进 30min，累计 ≤240min）', () => {
    it('步进非 30 的倍数 → VALIDATION_ERROR', () => {
      const r = makeRecord();
      expect(() => fasting.extend(userId, randomUUID(), r.id, 45)).toThrow(
        expect.objectContaining({ code: 'VALIDATION_ERROR' }) as unknown as Error,
      );
    });

    it('延长 30min：plannedEndAt 后移，剩余额度 210', () => {
      const r = makeRecord();
      const res = fasting.extend(userId, randomUUID(), r.id, 30) as {
        plannedEndAt: string;
        extendedMinutes: number;
        extendRemainingMinutes: number;
      };
      expect(res.plannedEndAt).toBe('2026-07-27T04:30:00.000Z');
      expect(res.extendedMinutes).toBe(30);
      expect(res.extendRemainingMinutes).toBe(210);
    });

    it('累计达 240 后再延长 → 400 FASTING_EXTEND_LIMIT（上限 4h）', () => {
      const r = makeRecord();
      for (let i = 0; i < MAX_EXTEND_MINUTES / 30; i++) {
        fasting.extend(userId, randomUUID(), r.id, 30);
      }
      expect(store.fastingRecords.get(r.id)!.extendedMinutes).toBe(240);
      expect(() => fasting.extend(userId, randomUUID(), r.id, 30)).toThrow(
        expect.objectContaining({
          code: 'FASTING_EXTEND_LIMIT',
          details: { extendRemainingMinutes: 0 },
        }) as unknown as Error,
      );
    });

    it('单次延长超过剩余额度 → FASTING_EXTEND_LIMIT，剩余额度见 details', () => {
      const r = makeRecord({ extendedMinutes: 210 });
      expect(() => fasting.extend(userId, randomUUID(), r.id, 60)).toThrow(
        expect.objectContaining({
          code: 'FASTING_EXTEND_LIMIT',
          details: { extendRemainingMinutes: 30 },
        }) as unknown as Error,
      );
    });
  });
});
