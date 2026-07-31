import { EstimateService } from '../src/llm/estimate.service';
import { LlmEstimate, LlmEstimateProvider } from '../src/llm/llm-estimate.types';
import { OpenAiCompatibleProvider } from '../src/llm/openai-compatible.provider';
import { StubProvider } from '../src/llm/stub.provider';

function mockFetchOk(content: string): typeof fetch {
  return (() =>
    Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ choices: [{ message: { content } }] }),
    } as Response)) as unknown as typeof fetch;
}

describe('LLM 营养估算 Provider', () => {
  it('StubProvider（未配置供应商）直接抛 ESTIMATE_UNAVAILABLE', async () => {
    await expect(new StubProvider().estimate('红烧肉')).rejects.toMatchObject({
      code: 'ESTIMATE_UNAVAILABLE',
    });
  });

  it('OpenAiCompatibleProvider：custom（Ollama）成功解析 JSON', async () => {
    const fetchFn = mockFetchOk(
      '{"kcal": 250, "protein_g": 12.5, "carb_g": 8.0, "fat_g": 18.2, "confidence": "medium"}',
    );
    const provider = new OpenAiCompatibleProvider({
      name: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:4b',
      fetchFn,
    });
    const est = await provider.estimate('番茄炒蛋');
    expect(est.per100g).toEqual({ kcal: 250, proteinG: 12.5, carbG: 8.0, fatG: 18.2 });
    expect(est.confidence).toBe('medium');
  });

  it('请求参数：temperature=0.2、URL 拼接、无 key 时不带 authorization 头', async () => {
    let captured: { url: string; init: RequestInit } | null = null;
    const fetchFn = ((url: string, init: RequestInit) => {
      captured = { url, init };
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            choices: [
              {
                message: {
                  content: '{"kcal":100,"protein_g":1,"carb_g":1,"fat_g":1,"confidence":"high"}',
                },
              },
            ],
          }),
      } as Response);
    }) as unknown as typeof fetch;
    const provider = new OpenAiCompatibleProvider({
      name: 'custom',
      baseUrl: 'http://localhost:11434/v1/',
      model: 'qwen3:4b',
      fetchFn,
    });
    await provider.estimate('米饭', '白米饭一碗');
    expect(captured!.url).toBe('http://localhost:11434/v1/chat/completions');
    expect((captured!.init.headers as Record<string, string>).authorization).toBeUndefined();
    const body = JSON.parse(captured!.init.body as string);
    expect(body.model).toBe('qwen3:4b');
    expect(body.temperature).toBe(0.2);
    expect(body.messages[0].role).toBe('system');
    expect(body.messages[1].content).toContain('米饭');
  });

  it('容忍 ```json 代码块包裹；缺省 confidence 按 low', async () => {
    const provider = new OpenAiCompatibleProvider({
      name: 'custom',
      baseUrl: 'http://x/v1',
      model: 'm',
      fetchFn: mockFetchOk('```json\n{"kcal": 50, "protein_g": 2, "carb_g": 3, "fat_g": 1}\n```'),
    });
    const est = await provider.estimate('西兰花');
    expect(est.per100g.kcal).toBe(50);
    expect(est.confidence).toBe('low');
  });

  it('超时 → ESTIMATE_UNAVAILABLE', async () => {
    const fetchFn = ((_: string, init: RequestInit) =>
      new Promise((_, reject) => {
        init.signal?.addEventListener('abort', () =>
          reject(new DOMException('The operation was aborted', 'AbortError')),
        );
      })) as unknown as typeof fetch;
    const provider = new OpenAiCompatibleProvider({
      name: 'custom',
      baseUrl: 'http://x/v1',
      model: 'm',
      timeoutMs: 30,
      fetchFn,
    });
    await expect(provider.estimate('佛跳墙')).rejects.toMatchObject({
      code: 'ESTIMATE_UNAVAILABLE',
    });
  });

  it('非法 JSON / 缺字段 / HTTP 非 2xx → ESTIMATE_UNAVAILABLE', async () => {
    const mk = (fetchFn: unknown) =>
      new OpenAiCompatibleProvider({
        name: 'custom',
        baseUrl: 'http://x/v1',
        model: 'm',
        fetchFn: fetchFn as typeof fetch,
      });
    await expect(mk(mockFetchOk('这不是JSON')).estimate('x')).rejects.toMatchObject({
      code: 'ESTIMATE_UNAVAILABLE',
    });
    await expect(mk(mockFetchOk('{"kcal": 100}')).estimate('x')).rejects.toMatchObject({
      code: 'ESTIMATE_UNAVAILABLE',
    });
    const http500 = (() =>
      Promise.resolve({ ok: false, json: () => Promise.resolve({}) } as Response)) as unknown;
    await expect(mk(http500).estimate('x')).rejects.toMatchObject({
      code: 'ESTIMATE_UNAVAILABLE',
    });
  });
});

describe('EstimateService（缓存 + 校验）', () => {
  class FakeProvider implements LlmEstimateProvider {
    readonly name = 'fake';
    readonly model = 'm1';
    calls = 0;
    constructor(public result: LlmEstimate) {}
    estimate(): Promise<LlmEstimate> {
      this.calls += 1;
      return Promise.resolve(this.result);
    }
  }
  const good: LlmEstimate = {
    per100g: { kcal: 200, proteinG: 10, carbG: 20, fatG: 5 },
    confidence: 'high',
  };

  it('缓存：同名（大小写/空白归一）第二次命中，cached:true，provider 只调一次', async () => {
    const provider = new FakeProvider(good);
    const svc = new EstimateService(provider);
    const r1 = await svc.estimate('红烧肉');
    expect(r1).toMatchObject({ source: 'llm-estimate', cached: false, confidence: 'high' });
    const r2 = await svc.estimate('  红烧肉 ');
    expect(r2.cached).toBe(true);
    expect(r2.per100g).toEqual(good.per100g);
    expect(provider.calls).toBe(1);
  });

  it('菜名校验：trim 后 1-50 字，越界 VALIDATION_ERROR', async () => {
    const svc = new EstimateService(new FakeProvider(good));
    await expect(svc.estimate('   ')).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    await expect(svc.estimate('a'.repeat(51))).rejects.toMatchObject({
      code: 'VALIDATION_ERROR',
    });
  });

  it('营养越界（kcal>900 或 宏量>100）拒绝且不缓存', async () => {
    const bad: LlmEstimate = {
      per100g: { kcal: 1200, proteinG: 10, carbG: 20, fatG: 5 },
      confidence: 'low',
    };
    const provider = new FakeProvider(bad);
    const svc = new EstimateService(provider);
    await expect(svc.estimate('炸弹')).rejects.toMatchObject({ code: 'ESTIMATE_UNAVAILABLE' });
    provider.result = good;
    const r = await svc.estimate('炸弹');
    expect(r.cached).toBe(false); // 未缓存坏结果，修复后可重试成功
    expect(provider.calls).toBe(2);
  });
});
