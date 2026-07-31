import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { mkdtempSync, readFileSync, rmSync } from 'fs';
import { createServer } from 'http';
import type { AddressInfo } from 'net';
import { tmpdir } from 'os';
import { join } from 'path';
import request from 'supertest';
import { AppModule } from '../src/app.module';

const ADMIN = 'test-admin-token';

/**
 * e2e：管理控制台 API 配置（/v1/admin/config*）+ /admin 静态页。
 * 覆盖：token 保护、PUT 校验、覆盖优先级（source=runtime）、key 脱敏、
 * test 端点三态（stub 失败 / custom 成功 / custom 不可达失败）、持久化落盘。
 */
describe('Admin config & console (e2e)', () => {
  let app: INestApplication;
  let server: Parameters<typeof request>[0];
  let cfgDir: string;
  let cfgFile: string;
  let mockLlm: ReturnType<typeof createServer>;
  let mockBaseUrl: string;

  const authHeader = { 'x-admin-token': ADMIN };

  beforeAll(async () => {
    cfgDir = mkdtempSync(join(tmpdir(), 'eatwise-admin-e2e-'));
    cfgFile = join(cfgDir, 'admin-config.json');
    process.env.ADMIN_CONFIG_PATH = cfgFile;
    process.env.ADMIN_TOKEN = ADMIN;
    process.env.LLM_PROVIDER = 'stub'; // 盖掉 .env，保证初始态确定

    // 本地 OpenAI 兼容 mock：验证 custom 配置真实打通
    mockLlm = createServer((req, res) => {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        res.setHeader('content-type', 'application/json');
        res.end(
          JSON.stringify({
            choices: [
              {
                message: {
                  content:
                    '{"kcal": 116, "protein_g": 2.6, "carb_g": 25.9, "fat_g": 0.3, "confidence": "high"}',
                },
              },
            ],
          }),
        );
      });
    });
    await new Promise<void>((resolve) => mockLlm.listen(0, '127.0.0.1', resolve));
    mockBaseUrl = `http://127.0.0.1:${(mockLlm.address() as AddressInfo).port}/v1`;

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: [{ path: 'admin', method: RequestMethod.GET }] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    server = app.getHttpServer() as Parameters<typeof request>[0];
  });

  afterAll(async () => {
    await app.close();
    await new Promise<void>((resolve) => mockLlm.close(() => resolve()));
    rmSync(cfgDir, { recursive: true, force: true });
    delete process.env.ADMIN_CONFIG_PATH;
    delete process.env.ADMIN_TOKEN;
    delete process.env.LLM_PROVIDER;
  });

  describe('token 保护（同 admin-food）', () => {
    it('缺 header / 错 token → 401', async () => {
      await request(server).get('/v1/admin/config').expect(401);
      await request(server).get('/v1/admin/config').set('x-admin-token', 'wrong').expect(401);
      await request(server).put('/v1/admin/config/llm').send({ provider: 'stub' }).expect(401);
      await request(server)
        .post('/v1/admin/config/llm/test')
        .set('x-admin-token', 'wrong')
        .expect(401);
    });
  });

  describe('GET /v1/admin/config', () => {
    it('默认（env LLM_PROVIDER=stub）→ source=stub', async () => {
      const res = await request(server).get('/v1/admin/config').set(authHeader).expect(200);
      expect(res.body.data.llm.provider).toBe('stub');
      expect(res.body.data.llm.source).toBe('stub');
      expect(res.body.data.llm.apiKey).toBeNull();
      expect(res.body.data.override).toBeNull();
      expect(res.body.data.persisted).toBe(true);
    });
  });

  describe('PUT /v1/admin/config/llm 校验', () => {
    it('provider 枚举外 → 400', async () => {
      await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({ provider: 'gpt4' })
        .expect(400);
    });

    it('provider=custom 缺 baseUrl/model → 400 VALIDATION_ERROR', async () => {
      const res = await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({ provider: 'custom', model: 'qwen3:4b' })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });
  });

  describe('运行时覆盖生效（免重启）', () => {
    it('PUT custom 完整四元组 → source=runtime，apiKey 脱敏返回，文件落盘', async () => {
      const res = await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({
          provider: 'custom',
          baseUrl: mockBaseUrl,
          model: 'qwen3:4b',
          apiKey: 'sk-e2e-key-123456',
        })
        .expect(200);
      expect(res.body.data.llm.source).toBe('runtime');
      expect(res.body.data.llm.provider).toBe('custom');
      expect(res.body.data.llm.apiKey).toBe('sk-***3456');
      expect(JSON.stringify(res.body.data)).not.toContain('sk-e2e-key-123456');

      const onDisk = JSON.parse(readFileSync(cfgFile, 'utf8')) as { llm: Record<string, string> };
      expect(onDisk.llm).toMatchObject({
        provider: 'custom',
        baseUrl: mockBaseUrl,
        model: 'qwen3:4b',
        apiKey: 'sk-e2e-key-123456',
      });
    });

    it('apiKey 留空 = 保持不变', async () => {
      const res = await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({ provider: 'custom', baseUrl: mockBaseUrl, model: 'qwen3:4b' })
        .expect(200);
      expect(res.body.data.llm.apiKey).toBe('sk-***3456');
    });

    it('POST llm/test：custom 指向本地 mock → ok:true，返回白米饭估算', async () => {
      const res = await request(server)
        .post('/v1/admin/config/llm/test')
        .set(authHeader)
        .expect(200);
      expect(res.body.data.ok).toBe(true);
      expect(res.body.data.provider).toBe('custom');
      expect(res.body.data.result.per100g).toEqual({
        kcal: 116,
        proteinG: 2.6,
        carbG: 25.9,
        fatG: 0.3,
      });
      expect(res.body.data.result.confidence).toBe('high');
    });

    it('POST llm/test：端点不可达 → ok:false + 错误详情（ESTIMATE_UNAVAILABLE）', async () => {
      await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({ provider: 'custom', baseUrl: 'http://127.0.0.1:1/v1', model: 'qwen3:4b' })
        .expect(200);
      const res = await request(server)
        .post('/v1/admin/config/llm/test')
        .set(authHeader)
        .expect(200);
      expect(res.body.data.ok).toBe(false);
      expect(res.body.data.error.code).toBe('ESTIMATE_UNAVAILABLE');
    });

    it('POST llm/test：provider=stub → ok:false（ESTIMATE_UNAVAILABLE）', async () => {
      await request(server)
        .put('/v1/admin/config/llm')
        .set(authHeader)
        .send({ provider: 'stub' })
        .expect(200);
      const res = await request(server)
        .post('/v1/admin/config/llm/test')
        .set(authHeader)
        .expect(200);
      expect(res.body.data.ok).toBe(false);
      expect(res.body.data.provider).toBe('stub');
      expect(res.body.data.error.code).toBe('ESTIMATE_UNAVAILABLE');
    });
  });

  describe('GET /admin 管理控制台静态页', () => {
    it('返回 200 HTML，包含关键元素；不带 /v1 前缀', async () => {
      const res = await request(server).get('/admin').expect(200);
      expect(res.headers['content-type']).toContain('text/html');
      expect(res.text).toContain('管理控制台');
      expect(res.text).toContain('x-admin-token');
      expect(res.text).toContain('/admin/food-candidates');
      expect(res.text).toContain('/admin/config');
    });
  });
});
