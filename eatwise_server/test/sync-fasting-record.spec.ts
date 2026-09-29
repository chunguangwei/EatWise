import { randomUUID } from 'crypto';
import { DataStore, FastingRecordEntity } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { NutritionService } from '../src/nutrition/nutrition.service';
import { StreakService } from '../src/streak/streak.service';
import { SyncService } from '../src/sync/sync.service';

/** fastingRecord /sync 同日双端分叉 LWW（2026-09-29 拍板确定性收敛）：
 * 终态对终态按 updatedAt 覆盖；on_track 永不覆盖（F2/ghost 链路拥有）；
 * 缺 updatedAtUtc（旧客户端）保持「不覆盖」旧口径；行为幂等稳定。 */
describe('SyncService fastingRecord LWW', () => {
  const userId = 'u-lww';
  let store: DataStore;
  let driver: MemoryStoreDriver;
  let sync: SyncService;

  const basePayload = {
    attributionDate: '2026-08-01',
    plannedStartAt: '2026-07-31T12:00:00.000Z',
    plannedEndAt: '2026-08-01T04:00:00.000Z',
    actualStartAt: '2026-07-31T12:00:00.000Z',
    actualEndAt: '2026-08-01T04:00:00.000Z',
    extendedMinutes: 0,
    result: 'completed',
    isQualified: true,
  };

  beforeEach(() => {
    store = new DataStore();
    driver = new MemoryStoreDriver(store);
    sync = new SyncService(driver, new NutritionService(driver), new StreakService(driver));
    store.createUser({ id: userId, phone: '+8613900000042' });
  });

  function seedTerminal(updatedAt: Date): FastingRecordEntity {
    const record: FastingRecordEntity = {
      id: 'srv-seed',
      userId,
      attributionDate: '2026-08-01',
      plannedStartAt: new Date('2026-07-31T12:00:00.000Z'),
      plannedEndAt: new Date('2026-08-01T04:00:00.000Z'),
      actualStartAt: new Date('2026-07-31T12:00:00.000Z'),
      actualEndAt: new Date('2026-08-01T01:00:00.000Z'), // broken：提前结束
      extendedMinutes: 0,
      fastedMinutes: 13 * 60,
      result: 'broken',
      isQualified: false,
      eventLog: [],
      clientRequestId: null,
      version: 1,
      createdAt: updatedAt,
      updatedAt,
      deletedAt: null,
    };
    store.fastingRecords.set(record.id, record);
    return record;
  }

  const createOp = (payload: Record<string, unknown>) => ({
    clientRequestId: randomUUID(),
    entity: 'fastingRecord',
    op: 'create',
    payload,
  });

  it('终态对终态：客户端 updatedAtUtc 更晚 → 覆盖服务端内容（streak 重算）；重复上行幂等不再写', async () => {
    const seed = seedTerminal(new Date('2026-08-01T06:00:00.000Z'));

    const res = await sync.push(userId, [
      createOp({ ...basePayload, updatedAtUtc: '2026-08-02T00:00:00.000Z' }),
    ]);
    expect(res.results[0].status).toBe('applied');
    // 覆盖的是同一行（id 不变），内容取客户端较新版本。
    const after = (await driver.findFastingRecordById(seed.id))!;
    expect(after.result).toBe('completed');
    expect(after.isQualified).toBe(true);
    expect(after.fastedMinutes).toBe(16 * 60);
    expect(after.version).toBe(2);
    expect(after.eventLog.map((e) => e.event)).toContain('synced_overwrite');
    expect((res.results[0].serverEntry as { id: string }).id).toBe(seed.id);
    // streak 重算：broken→completed，达标集合 +1。
    const streak = await driver.findStreakByUser(userId);
    expect(streak?.longestStreak).toBeGreaterThanOrEqual(1);

    // 幂等稳定：同载荷（同 updatedAtUtc）重放不再新于覆盖后的 updatedAt → 不再写。
    const versionBefore = after.version;
    const replay = await sync.push(userId, [
      createOp({ ...basePayload, updatedAtUtc: '2026-08-02T00:00:00.000Z' }),
    ]);
    expect(replay.results[0].status).toBe('applied');
    expect((await driver.findFastingRecordById(seed.id))!.version).toBe(versionBefore);
  });

  it('客户端 updatedAtUtc 更旧 / 缺省（旧客户端）→ 不覆盖，返回既有视图', async () => {
    const seed = seedTerminal(new Date('2026-08-01T06:00:00.000Z'));

    const older = await sync.push(userId, [
      createOp({ ...basePayload, updatedAtUtc: '2026-07-31T00:00:00.000Z' }),
    ]);
    expect(older.results[0].status).toBe('applied');
    expect((await driver.findFastingRecordById(seed.id))!.result).toBe('broken');

    const legacy = await sync.push(userId, [createOp({ ...basePayload })]);
    expect(legacy.results[0].status).toBe('applied');
    const after = (await driver.findFastingRecordById(seed.id))!;
    expect(after.result).toBe('broken'); // 旧口径：不覆盖
    expect(after.version).toBe(1);
  });

  it('on_track 进行中记录永不被 /sync 覆盖（F2/ghost 结算链路拥有）', async () => {
    const seed = seedTerminal(new Date('2026-08-01T06:00:00.000Z'));
    seed.result = 'on_track';
    seed.actualEndAt = null;
    seed.isQualified = false;

    const res = await sync.push(userId, [
      createOp({ ...basePayload, updatedAtUtc: '2999-08-02T00:00:00.000Z' }),
    ]);
    expect(res.results[0].status).toBe('applied'); // 幂等返回既有视图
    const after = (await driver.findFastingRecordById(seed.id))!;
    expect(after.result).toBe('on_track'); // 未被覆盖
    expect(after.actualEndAt).toBeNull();
    expect(after.version).toBe(1);
  });
});
