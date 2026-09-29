import { randomUUID } from 'crypto';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：fastingRecord 经 /v1/sync push/pull 全链路上下行（2026-09-29 拍板
 * 全量进 /sync：换机全量恢复断食历史；HTTP + DTO 校验 + 鉴权 + 归属日幂等 +
 * tombstone；STORE_DRIVER=memory 默认）。 */
describe('FastingRecord sync (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;

  const payload = {
    attributionDate: '2026-08-01',
    plannedStartAt: '2026-07-31T12:00:00.000Z',
    plannedEndAt: '2026-08-01T04:00:00.000Z',
    actualStartAt: '2026-07-31T12:00:00.000Z',
    actualEndAt: '2026-08-01T04:00:00.000Z',
    extendedMinutes: 0,
    result: 'completed',
    isQualified: true,
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    await request(server)
      .post('/v1/auth/sms/send')
      .send({ phone: '+8613922000077', scene: 'login' })
      .expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({
        phone: '+8613922000077',
        code: '123456',
        device: { deviceId: 'e2e-fasting-record', platform: 'ios' },
      })
      .expect(200);
    token = res.body.data.accessToken as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = () => ({ Authorization: `Bearer ${token}` });

  it('push create → pull 下行（跨端可见，换机全量恢复）→ push delete → pull tombstone', async () => {
    const clientRequestId = randomUUID();
    // A 机上行：本地关闭的断食周期（达标）。
    const push1 = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({ ops: [{ clientRequestId, entity: 'fastingRecord', op: 'create', payload }] })
      .expect(200);
    expect(push1.body.data.results[0].status).toBe('applied');
    const serverEntry = push1.body.data.results[0].serverEntry;
    expect(serverEntry.entity).toBe('fastingRecord');
    expect(serverEntry.attributionDate).toBe('2026-08-01');
    expect(serverEntry.isQualified).toBe(true);
    expect(serverEntry.fastedMinutes).toBe(16 * 60); // 未传 fastedMinutes → 服务端推导
    const serverId = serverEntry.id as string;

    // 幂等重放：同键同体返回首次结果。
    const replay = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({ ops: [{ clientRequestId, entity: 'fastingRecord', op: 'create', payload }] })
      .expect(200);
    expect(replay.body.data.results[0].serverEntry.id).toBe(serverId);

    // 同键不同体 → IDEMPOTENCY_PAYLOAD_MISMATCH。
    const mismatch = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId,
            entity: 'fastingRecord',
            op: 'create',
            payload: { ...payload, result: 'broken', isQualified: false },
          },
        ],
      })
      .expect(200);
    expect(mismatch.body.data.results[0].error.code).toBe('IDEMPOTENCY_PAYLOAD_MISMATCH');

    // 归属日天然幂等键：不同幂等键、同归属日 → 不覆盖既有记录，返回既有视图。
    const dupDate = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'create',
            payload: { ...payload, result: 'broken', isQualified: false },
          },
        ],
      })
      .expect(200);
    expect(dupDate.body.data.results[0].status).toBe('applied');
    expect(dupDate.body.data.results[0].serverEntry.id).toBe(serverId);
    expect(dupDate.body.data.results[0].serverEntry.result).toBe('completed');

    // streak 重算：新落达标记录并入权威口径（S1 可见）。
    const streak = await request(server).get('/v1/streak').set(auth()).expect(200);
    expect(streak.body.data.longestStreak).toBeGreaterThanOrEqual(1);

    // B 机首次同步（无 syncToken）→ 全量下行能看到（>14 天历史也经本通道恢复）。
    const pull1 = await request(server).get('/v1/sync/pull').set(auth()).expect(200);
    const changes = pull1.body.data.fastingRecordChanges as Array<Record<string, unknown>>;
    expect(changes.length).toBe(1);
    expect(changes[0].id).toBe(serverId);
    expect(changes[0].attributionDate).toBe('2026-08-01');
    expect(changes[0].result).toBe('completed');

    // A 机删除（tombstone 上行 delete；serverId + 幂等键双定位）。
    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    const del = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'delete',
            serverId,
            payload: { clientRequestId },
          },
        ],
      })
      .expect(200);
    expect(del.body.data.results[0].status).toBe('applied');

    // 删除把该日移出达标集合 → streak 重算回落。
    const streak2 = await request(server).get('/v1/streak').set(auth()).expect(200);
    expect(streak2.body.data.currentStreak).toBe(0);

    // B 机增量下行 → tombstone。
    const pull2 = await request(server)
      .get('/v1/sync/pull')
      .query({ syncToken: pull1.body.data.syncToken as string })
      .set(auth())
      .expect(200);
    const changes2 = pull2.body.data.fastingRecordChanges as Array<{
      tombstone?: { entity: string; id: string };
    }>;
    expect(changes2.length).toBe(1);
    expect(changes2[0].tombstone?.entity).toBe('fastingRecord');
    expect(changes2[0].tombstone?.id).toBe(serverId);

    // F4 轻量回填接口不再返回已删记录（tombstone 隐藏）。
    const f4 = await request(server)
      .get('/v1/fasting/records')
      .query({ from: '2026-08-01', to: '2026-08-01' })
      .set(auth())
      .expect(200);
    expect(f4.body.data).toHaveLength(0);
  });

  it('DTO 校验：on_track/缺锚点 → 逐条 VALIDATION_ERROR；entity 白名单含 fastingRecord；未带 token → 401', async () => {
    // on_track 进行中不经本通道（业务层校验 → 逐条 error，整体不失败）。
    const onTrack = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'create',
            payload: { ...payload, attributionDate: '2026-08-02', result: 'on_track' },
          },
        ],
      })
      .expect(400); // DTO result 枚举拒绝（白名单外）
    expect(onTrack.body.error.code).toBe('VALIDATION_ERROR');

    const missingAnchor = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'fastingRecord',
            op: 'create',
            payload: { attributionDate: '2026-08-03', result: 'completed', isQualified: true },
          },
        ],
      })
      .expect(200);
    expect(missingAnchor.body.data.results[0].status).toBe('error');
    expect(missingAnchor.body.data.results[0].error.code).toBe('VALIDATION_ERROR');

    await request(server)
      .post('/v1/sync/push')
      .send({
        ops: [{ clientRequestId: randomUUID(), entity: 'fastingRecord', op: 'create', payload }],
      })
      .expect(401);
  });
});
