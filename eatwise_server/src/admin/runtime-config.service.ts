import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { PROVIDER_PRESETS } from '../llm/openai-compatible.provider';

/** 管理端可运行时修改的 LLM 供应商枚举（与 env LLM_PROVIDER 一致） */
export const LLM_PROVIDERS = ['stub', 'deepseek', 'qwen', 'kimi', 'custom'] as const;
export type LlmProviderName = (typeof LLM_PROVIDERS)[number];

/** 运行时覆盖项（持久化到 data/admin-config.json）；字段缺省 = 该项回退 env */
export interface LlmOverride {
  provider?: LlmProviderName;
  baseUrl?: string;
  model?: string;
  apiKey?: string;
}

export type LlmConfigSource = 'runtime' | 'env' | 'stub';

/** 生效配置（override 逐字段优先于 env；内置供应商补 preset 默认值） */
export interface EffectiveLlmConfig {
  provider: string;
  baseUrl?: string;
  model?: string;
  apiKey?: string;
  source: LlmConfigSource;
}

/** apiKey 脱敏：仅保留后 4 位（`sk-***xxxx`）；≤4 位全遮；无 key 返回 null */
export function maskApiKey(key?: string): string | null {
  if (!key) return null;
  if (key.length <= 4) return '***';
  return `sk-***${key.slice(-4)}`;
}

/**
 * 运行时配置存储（管理控制台「API 配置」页）：读优先级 = 运行时覆盖 > env。
 * 覆盖项持久化到本地 JSON（默认 data/admin-config.json，可用 ADMIN_CONFIG_PATH 改路径，
 * 主要供测试隔离）；文件读写失败降级为仅内存并告警，不影响请求链路。
 */
@Injectable()
export class RuntimeConfigService {
  private readonly logger = new Logger(RuntimeConfigService.name);
  private readonly filePath: string;
  private llmOverride: LlmOverride = {};
  /** 最近一次持久化是否成功（失败=仅内存生效，重启丢失；GET /v1/admin/config 透出） */
  private persisted = true;

  constructor(private readonly env: ConfigService) {
    this.filePath =
      process.env.ADMIN_CONFIG_PATH ?? join(process.cwd(), 'data', 'admin-config.json');
    this.load();
  }

  private load() {
    try {
      if (!existsSync(this.filePath)) return;
      const raw = JSON.parse(readFileSync(this.filePath, 'utf8')) as { llm?: LlmOverride };
      this.llmOverride = raw.llm ?? {};
      this.logger.log(`已加载运行时配置：${this.filePath}`);
    } catch (e) {
      this.logger.warn(
        `读取 ${this.filePath} 失败，运行时配置按空处理（仅内存）：${(e as Error).message}`,
      );
      this.llmOverride = {};
    }
  }

  private persist() {
    try {
      mkdirSync(dirname(this.filePath), { recursive: true });
      writeFileSync(this.filePath, JSON.stringify({ llm: this.llmOverride }, null, 2), 'utf8');
      this.persisted = true;
    } catch (e) {
      this.persisted = false;
      this.logger.warn(
        `写入 ${this.filePath} 失败，运行时配置仅本次进程内生效：${(e as Error).message}`,
      );
    }
  }

  isPersisted(): boolean {
    return this.persisted;
  }

  /** 当前存储的覆盖项（原始值，含 apiKey；对外输出前必须脱敏） */
  getLlmOverride(): LlmOverride {
    return { ...this.llmOverride };
  }

  /**
   * 更新 LLM 覆盖项并持久化。provider 必传；baseUrl/model 提供则覆盖；
   * apiKey 留空（undefined/空串）= 保持不变（控制台密码框语义）。
   * provider 变更时重置 baseUrl/model/apiKey 覆盖项：否则从 custom 切回 preset 后
   * 旧值仍压过 preset 默认值（串味）。
   */
  setLlmOverride(patch: LlmOverride): void {
    const providerChanged =
      patch.provider !== undefined && patch.provider !== this.llmOverride.provider;
    const next: LlmOverride = providerChanged ? {} : { ...this.llmOverride };
    if (patch.provider !== undefined) next.provider = patch.provider;
    if (patch.baseUrl?.trim()) next.baseUrl = patch.baseUrl.trim();
    if (patch.model?.trim()) next.model = patch.model.trim();
    if (patch.apiKey?.trim()) next.apiKey = patch.apiKey.trim();
    this.llmOverride = next;
    this.persist();
  }

  /**
   * 计算生效 LLM 配置（每次调用现算，供 RuntimeLlmProvider 实现免重启切换）。
   * source：runtime = 覆盖项指定了 provider；env = env LLM_PROVIDER 指定了非 stub；
   * stub = 均未配置（端点返回 ESTIMATE_UNAVAILABLE，客户端降级手动填写）。
   */
  resolveLlm(): EffectiveLlmConfig {
    const o = this.llmOverride;
    if (o.provider) {
      const preset = PROVIDER_PRESETS[o.provider];
      return {
        provider: o.provider,
        baseUrl: o.baseUrl || this.env.get<string>('LLM_BASE_URL') || preset?.baseUrl,
        model: o.model || this.env.get<string>('LLM_MODEL') || preset?.model,
        apiKey: o.apiKey || this.env.get<string>('LLM_API_KEY') || undefined,
        source: 'runtime',
      };
    }
    const envProvider = (this.env.get<string>('LLM_PROVIDER') ?? 'stub').trim().toLowerCase();
    if (envProvider && envProvider !== 'stub') {
      const preset = PROVIDER_PRESETS[envProvider];
      return {
        provider: envProvider,
        baseUrl: this.env.get<string>('LLM_BASE_URL') || preset?.baseUrl,
        model: this.env.get<string>('LLM_MODEL') || preset?.model,
        apiKey: this.env.get<string>('LLM_API_KEY') || undefined,
        source: 'env',
      };
    }
    return { provider: 'stub', source: 'stub' };
  }
}
