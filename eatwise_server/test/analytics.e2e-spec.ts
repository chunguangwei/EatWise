import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

/** e2e：/v1/analytics/events 采集网关（匿名 202 接收；坏载荷 400） */
describe('Analytics events ingest (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];

  beforeAll(async () => {
    process.env.ANALYTICS_LOG_PATH = `data/analytics-events-e2e-${Date.now()}.jsonl`;
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
  });

  const batch = {
    data: {
      events: [
        {
          event_id: '3f6b9d3e-0d6f-4b3f-9c4a-1a2b3c4d5e6f',
          event_name: 'record_flow_success',
          timestamp: 1790000000000,
          client_date: '2026-09-29',
          common: { anon_id: 'hmac-xyz' },
          properties: { record_kind: 'water' },
        },
      ],
    },
    meta: { requestId: 'req-1', clientTime: '2026-09-29T01:00:00.000Z' },
  };

  it('匿名批量上报 → 202 accepted', async () => {
    // 不带 Authorization：生产客户端裸 Dio 不上认证头
    const res = await request(server).post('/v1/analytics/events').send(batch).expect(202);
    expect(res.body.data.accepted).toBe(1);
  });

  it('坏载荷（events 非数组 / 缺 meta）→ 400；空批 202 accepted=0', async () => {
    await request(server)
      .post('/v1/analytics/events')
      .send({ data: { events: 'nope' }, meta: { requestId: 'r' } })
      .expect(400);
    await request(server)
      .post('/v1/analytics/events')
      .send({ data: { events: [] } })
      .expect(400);
    const empty = await request(server)
      .post('/v1/analytics/events')
      .send({ data: { events: [] }, meta: { requestId: 'r' } })
      .expect(202);
    expect(empty.body.data.accepted).toBe(0);
  });
});
