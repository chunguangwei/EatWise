import { randomUUID } from 'crypto';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：exerciseLog 经 /v1/sync push/pull 全链路上下行（HTTP + DTO 校验 +
 * 鉴权 + 跨端合并口径；STORE_DRIVER=memory 默认）。 */
describe('ExerciseLog sync (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let token: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];

    await request(server)
      .post('/v1/auth/sms/send')
      .send({ phone: '+8613922000099', scene: 'login' })
      .expect(200);
    const res = await request(server)
      .post('/v1/auth/login/phone')
      .send({
        phone: '+8613922000099',
        code: '123456',
        device: { deviceId: 'e2e-exercise', platform: 'android' },
      })
      .expect(200);
    token = res.body.data.accessToken as string;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = () => ({ Authorization: `Bearer ${token}` });

  it('push create → pull 下行（跨端可见）→ push delete → pull tombstone', async () => {
    const clientRequestId = randomUUID();
    // A 机上行：手动录入运动（含步数快照 + 截图来源标记）。
    const push1 = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId,
            entity: 'exerciseLog',
            op: 'create',
            payload: {
              typeKey: 'walk',
              durationMin: 0,
              kcal: 68,
              steps: 1466,
              source: 'screenshot',
              loggedAt: '2026-09-19T02:00:00.000Z',
              localDate: '2026-09-19',
            },
          },
        ],
      })
      .expect(200);
    expect(push1.body.data.results[0].status).toBe('applied');
    const serverId = push1.body.data.results[0].serverEntry.id as string;

    // 幂等重放：同键同体返回首次结果。
    const replay = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId,
            entity: 'exerciseLog',
            op: 'create',
            payload: {
              typeKey: 'walk',
              durationMin: 0,
              kcal: 68,
              steps: 1466,
              source: 'screenshot',
              loggedAt: '2026-09-19T02:00:00.000Z',
              localDate: '2026-09-19',
            },
          },
        ],
      })
      .expect(200);
    expect(replay.body.data.results[0].serverEntry.id).toBe(serverId);

    // B 机首次同步（无 syncToken）→ 全量下行能看到。
    const pull1 = await request(server).get('/v1/sync/pull').set(auth()).expect(200);
    const changes = pull1.body.data.exerciseLogChanges as Array<Record<string, unknown>>;
    expect(changes.length).toBe(1);
    expect(changes[0].id).toBe(serverId);
    expect(changes[0].typeKey).toBe('walk');
    expect(changes[0].steps).toBe(1466);
    expect(changes[0].kcal).toBe(68);

    // A 机撤销（tombstone 上行 delete）。
    await new Promise((r) => setTimeout(r, 5)); // 保证 updatedAt 递增
    await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'exerciseLog',
            op: 'delete',
            serverId,
            payload: { clientRequestId },
          },
        ],
      })
      .expect(200);

    // B 机增量下行 → tombstone。
    const pull2 = await request(server)
      .get('/v1/sync/pull')
      .query({ syncToken: pull1.body.data.syncToken as string })
      .set(auth())
      .expect(200);
    const changes2 = pull2.body.data.exerciseLogChanges as Array<{
      tombstone?: { entity: string; id: string };
    }>;
    expect(changes2.length).toBe(1);
    expect(changes2[0].tombstone?.entity).toBe('exerciseLog');
    expect(changes2[0].tombstone?.id).toBe(serverId);
  });

  it('DTO 校验：缺 loggedAt → 逐条 VALIDATION_ERROR；entity 非法 → 400；未带 token → 401', async () => {
    // loggedAt 在 DTO 为可空，业务层校验 → 逐条 error（整体不失败，§2.3）。
    const bad = await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'exerciseLog',
            op: 'create',
            payload: { typeKey: 'jog', durationMin: 30, kcal: 210 },
          },
        ],
      })
      .expect(200);
    expect(bad.body.data.results[0].status).toBe('error');
    expect(bad.body.data.results[0].error.code).toBe('VALIDATION_ERROR');

    await request(server)
      .post('/v1/sync/push')
      .set(auth())
      .send({
        ops: [{ clientRequestId: randomUUID(), entity: 'stepLog', op: 'create', payload: {} }],
      })
      .expect(400); // entity 不在白名单

    await request(server)
      .post('/v1/sync/push')
      .send({
        ops: [
          {
            clientRequestId: randomUUID(),
            entity: 'exerciseLog',
            op: 'create',
            payload: {
              typeKey: 'jog',
              durationMin: 30,
              kcal: 210,
              loggedAt: '2026-09-19T02:00:00.000Z',
            },
          },
        ],
      })
      .expect(401);
  });
});
