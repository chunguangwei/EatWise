import { Logger } from '@nestjs/common';
import { LlmEstimateProvider } from './llm-estimate.types';
import { OpenAiCompatibleProvider, PROVIDER_PRESETS } from './openai-compatible.provider';
import { StubProvider } from './stub.provider';

export interface LlmProviderConfig {
  provider: string;
  baseUrl?: string;
  model?: string;
  apiKey?: string;
}

/**
 * 按生效配置构建 Provider（env 与管理端运行时覆盖共用同一构建逻辑）。
 * provider=stub 或 custom/未知供应商缺 baseUrl/model 时降级 Stub
 * （端点返回 ESTIMATE_UNAVAILABLE，客户端手动填写兜底）。
 */
export function buildLlmProvider(cfg: LlmProviderConfig): LlmEstimateProvider {
  const name = (cfg.provider ?? 'stub').trim().toLowerCase();
  if (name === 'stub') return new StubProvider();
  // 内置供应商（deepseek/qwen/kimi）未显式给 baseUrl/model 时补 preset 默认值〔假设〕
  const preset = PROVIDER_PRESETS[name];
  const baseUrl = cfg.baseUrl || preset?.baseUrl;
  const model = cfg.model || preset?.model;
  if (!baseUrl || !model) {
    new Logger('LlmModule').warn(`LLM_PROVIDER=${name} 缺少 BASE_URL/MODEL，降级 stub`);
    return new StubProvider();
  }
  return new OpenAiCompatibleProvider({
    name,
    baseUrl,
    model,
    apiKey: cfg.apiKey,
  });
}

/**
 * 运行时感知的 Provider 包装：每次估算现算生效配置（运行时覆盖 > env），
 * 配置签名变化时重建内部 Provider —— 管理端改 LLM 配置免重启生效。
 * name/model 为动态 getter，保证 EstimateService 缓存 key 随配置切换失效。
 */
export class RuntimeLlmProvider implements LlmEstimateProvider {
  private signature?: string;
  private inner?: LlmEstimateProvider;

  constructor(private readonly resolve: () => LlmProviderConfig) {}

  get name(): string {
    return this.innerProvider().name;
  }

  get model(): string | undefined {
    return this.innerProvider().model;
  }

  estimate(name: string, description?: string) {
    return this.innerProvider().estimate(name, description);
  }

  private innerProvider(): LlmEstimateProvider {
    const cfg = this.resolve();
    const signature = JSON.stringify(cfg);
    if (!this.inner || this.signature !== signature) {
      this.inner = buildLlmProvider(cfg);
      this.signature = signature;
    }
    return this.inner;
  }
}
