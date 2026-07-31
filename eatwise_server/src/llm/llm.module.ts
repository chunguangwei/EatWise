import { Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EstimateService } from './estimate.service';
import { LLM_ESTIMATE_PROVIDER, LlmEstimateProvider } from './llm-estimate.types';
import { OpenAiCompatibleProvider, PROVIDER_PRESETS } from './openai-compatible.provider';
import { StubProvider } from './stub.provider';

@Module({
  providers: [
    EstimateService,
    {
      // LLM_PROVIDER=stub（默认）/deepseek/qwen/kimi/custom。
      // custom 需显式配置 LLM_BASE_URL + LLM_MODEL（如本地 Ollama）；
      // 配置缺失时降级 Stub（端点返回 ESTIMATE_UNAVAILABLE，客户端手动填写兜底）。
      provide: LLM_ESTIMATE_PROVIDER,
      inject: [ConfigService],
      useFactory: (config: ConfigService): LlmEstimateProvider => {
        const name = (config.get<string>('LLM_PROVIDER') ?? 'stub').trim().toLowerCase();
        if (name === 'stub') return new StubProvider();
        const preset = PROVIDER_PRESETS[name];
        const baseUrl = config.get<string>('LLM_BASE_URL') || preset?.baseUrl;
        const model = config.get<string>('LLM_MODEL') || preset?.model;
        if (!baseUrl || !model) {
          new Logger('LlmModule').warn(
            `LLM_PROVIDER=${name} 缺少 LLM_BASE_URL/LLM_MODEL，降级 stub`,
          );
          return new StubProvider();
        }
        return new OpenAiCompatibleProvider({
          name,
          baseUrl,
          model,
          apiKey: config.get<string>('LLM_API_KEY') || undefined,
        });
      },
    },
  ],
  exports: [EstimateService, LLM_ESTIMATE_PROVIDER],
})
export class LlmModule {}
