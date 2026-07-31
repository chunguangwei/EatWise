import { err } from '../common/errors/business.exception';
import { EstimateConfidence, LlmEstimate, LlmEstimateProvider } from './llm-estimate.types';

export interface OpenAiCompatibleOptions {
  /** 供应商标识（deepseek/qwen/kimi/custom，缓存 key 组成部分） */
  name: string;
  baseUrl: string;
  model: string;
  /** 本地 Ollama 等免鉴权端点可留空 */
  apiKey?: string;
  /** 单次请求超时（默认 15s） */
  timeoutMs?: number;
  /** 可注入 mock（测试用），默认全局 fetch */
  fetchFn?: typeof fetch;
}

/** 内置供应商默认端点/型号（env 未显式给 LLM_BASE_URL / LLM_MODEL 时使用）〔假设〕 */
export const PROVIDER_PRESETS: Record<string, { baseUrl: string; model: string }> = {
  deepseek: { baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' }, // 〔假设〕
  qwen: {
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  }, // 〔假设〕
  kimi: { baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k' }, // 〔假设〕
};

const SYSTEM_PROMPT = [
  '你是中餐营养估算助手。根据用户给出的菜名（可能附带描述），估算每 100g 可食部的营养值。',
  '只返回 JSON，不要输出任何其他文字或 Markdown 代码块：',
  '{"kcal": number, "protein_g": number, "carb_g": number, "fat_g": number, "confidence": "high"|"medium"|"low"}',
  '约束：kcal 0-900，其余 0-100；confidence 表示你对该估算的把握程度。',
].join('\n');

/**
 * OpenAI 兼容端点 Provider（POST {baseUrl}/chat/completions）。
 * 覆盖 deepseek/qwen/kimi 及 custom（如本地 Ollama http://localhost:11434/v1）。
 * 失败/超时/非法 JSON 一律抛 ESTIMATE_UNAVAILABLE（产品决策：估算非关键路径，可降级）。
 */
export class OpenAiCompatibleProvider implements LlmEstimateProvider {
  readonly name: string;
  readonly model: string;
  private readonly baseUrl: string;
  private readonly apiKey?: string;
  private readonly timeoutMs: number;
  private readonly fetchFn: typeof fetch;

  constructor(opts: OpenAiCompatibleOptions) {
    this.name = opts.name;
    this.model = opts.model;
    this.baseUrl = opts.baseUrl.replace(/\/+$/, '');
    this.apiKey = opts.apiKey;
    this.timeoutMs = opts.timeoutMs ?? 15_000;
    this.fetchFn = opts.fetchFn ?? fetch;
  }

  async estimate(name: string, description?: string): Promise<LlmEstimate> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await this.fetchFn(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          ...(this.apiKey ? { authorization: `Bearer ${this.apiKey}` } : {}),
        },
        body: JSON.stringify({
          model: this.model,
          temperature: 0.2,
          messages: [
            { role: 'system', content: SYSTEM_PROMPT },
            {
              role: 'user',
              content: description ? `菜名：${name}\n描述：${description}` : `菜名：${name}`,
            },
          ],
        }),
        signal: controller.signal,
      });
      if (!res.ok) throw err.estimateUnavailable();
      const body = (await res.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = body.choices?.[0]?.message?.content;
      if (!content) throw err.estimateUnavailable();
      return this.parse(content);
    } catch (e) {
      if ((e as { code?: string }).code === 'ESTIMATE_UNAVAILABLE') throw e;
      throw err.estimateUnavailable();
    } finally {
      clearTimeout(timer);
    }
  }

  /** 容忍 ```json 代码块包裹；字段缺失/非数值视为非法输出 */
  private parse(content: string): LlmEstimate {
    const text = content
      .trim()
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```$/, '');
    let raw: Record<string, unknown>;
    try {
      raw = JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw err.estimateUnavailable();
    }
    const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : NaN);
    const kcal = num(raw.kcal);
    const proteinG = num(raw.protein_g);
    const carbG = num(raw.carb_g);
    const fatG = num(raw.fat_g);
    if ([kcal, proteinG, carbG, fatG].some(Number.isNaN)) throw err.estimateUnavailable();
    const confidence: EstimateConfidence = ['high', 'medium', 'low'].includes(
      raw.confidence as string,
    )
      ? (raw.confidence as EstimateConfidence)
      : 'low'; // 〔假设〕缺省/非法置信度按 low 处理
    return { per100g: { kcal, proteinG, carbG, fatG }, confidence, rawText: content };
  }
}
