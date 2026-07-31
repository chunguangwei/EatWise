import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RuntimeConfigService } from '../admin/runtime-config.service';
import { EstimateService } from './estimate.service';
import { LLM_ESTIMATE_PROVIDER, LlmEstimateProvider } from './llm-estimate.types';
import { RuntimeLlmProvider, buildLlmProvider } from './llm-provider.factory';

@Module({
  providers: [
    EstimateService,
    {
      // LLM_PROVIDER=stub（默认）/deepseek/qwen/kimi/custom，读优先级 = 运行时覆盖 > env。
      // custom 需显式配置 baseUrl + model（如本地 Ollama）；配置缺失时降级 Stub
      // （端点返回 ESTIMATE_UNAVAILABLE，客户端手动填写兜底）。
      // AdminModule 存在时包装为 RuntimeLlmProvider：管理端 PUT /v1/admin/config/llm 免重启生效；
      // 无 RuntimeConfigService（单测直接装配 LlmModule）时退回 env 一次性构建。
      provide: LLM_ESTIMATE_PROVIDER,
      inject: [ConfigService, { token: RuntimeConfigService, optional: true }],
      useFactory: (config: ConfigService, runtime?: RuntimeConfigService): LlmEstimateProvider => {
        if (runtime) return new RuntimeLlmProvider(() => runtime.resolveLlm());
        return buildLlmProvider({
          provider: config.get<string>('LLM_PROVIDER') ?? 'stub',
          baseUrl: config.get<string>('LLM_BASE_URL') || undefined,
          model: config.get<string>('LLM_MODEL') || undefined,
          apiKey: config.get<string>('LLM_API_KEY') || undefined,
        });
      },
    },
  ],
  exports: [EstimateService, LLM_ESTIMATE_PROVIDER],
})
export class LlmModule {}
