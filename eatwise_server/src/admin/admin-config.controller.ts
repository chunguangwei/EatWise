import { Body, Controller, Get, Headers, HttpCode, Inject, Post, Put } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { LLM_ESTIMATE_PROVIDER, LlmEstimateProvider } from '../llm/llm-estimate.types';
import {
  LLM_PROVIDERS,
  LlmProviderName,
  RuntimeConfigService,
  maskApiKey,
} from './runtime-config.service';

export class UpdateLlmConfigDto {
  @IsIn(LLM_PROVIDERS)
  provider!: LlmProviderName;

  @IsOptional()
  @IsString()
  baseUrl?: string;

  @IsOptional()
  @IsString()
  model?: string;

  /** 留空 = 保持不变（密码框语义） */
  @IsOptional()
  @IsString()
  apiKey?: string;
}

/**
 * 管理端：服务端 API 配置（LLM 运行时修改免重启）。
 * 保护方式同 admin-food：header `x-admin-token` 须匹配 env `ADMIN_TOKEN`；
 * env 未配置时一律 404（不暴露端点存在性），token 不匹配 401。
 */
@Public()
@Controller('admin/config')
export class AdminConfigController {
  constructor(
    private readonly runtime: RuntimeConfigService,
    private readonly config: ConfigService,
    @Inject(LLM_ESTIMATE_PROVIDER) private readonly llm: LlmEstimateProvider,
  ) {}

  /** 当前生效 LLM 配置（来源 runtime/env/stub）+ 已存覆盖项；apiKey 一律脱敏返回 */
  @Get()
  getConfig(@Headers('x-admin-token') token: string | undefined) {
    this.checkToken(token);
    return this.configView();
  }

  /** 更新 LLM 覆盖项（持久化 data/admin-config.json）；custom 时 baseUrl/model 必填 */
  @Put('llm')
  updateLlm(@Headers('x-admin-token') token: string | undefined, @Body() dto: UpdateLlmConfigDto) {
    this.checkToken(token);
    if (dto.provider === 'custom' && (!dto.baseUrl?.trim() || !dto.model?.trim())) {
      throw err.validation({
        baseUrl: 'provider=custom 时必填',
        model: 'provider=custom 时必填',
      });
    }
    this.runtime.setLlmOverride({
      provider: dto.provider,
      baseUrl: dto.baseUrl,
      model: dto.model,
      apiKey: dto.apiKey,
    });
    return this.configView();
  }

  /**
   * 用当前生效配置对固定菜名「白米饭」调一次估算，验证配置可用性。
   * 直调 Provider（绕过 EstimateService 30 天缓存），否则改了 baseUrl/apiKey
   * 但 provider/model 未变时会命中旧缓存、误判配置可用。
   * 始终 200：ok:true 带估算结果；ok:false 带错误详情（如 ESTIMATE_UNAVAILABLE）。
   */
  @Post('llm/test')
  @HttpCode(200)
  async testLlm(@Headers('x-admin-token') token: string | undefined) {
    this.checkToken(token);
    const eff = this.runtime.resolveLlm();
    try {
      const result = await this.llm.estimate('白米饭');
      return { ok: true, provider: eff.provider, model: eff.model ?? null, result };
    } catch (e) {
      const be = e as { code?: string; message?: string };
      return {
        ok: false,
        provider: eff.provider,
        model: eff.model ?? null,
        error: { code: be.code ?? 'UNKNOWN', message: be.message ?? String(e) },
      };
    }
  }

  private configView() {
    const eff = this.runtime.resolveLlm();
    const o = this.runtime.getLlmOverride();
    return {
      llm: {
        provider: eff.provider,
        baseUrl: eff.baseUrl ?? null,
        model: eff.model ?? null,
        apiKey: maskApiKey(eff.apiKey),
        source: eff.source,
      },
      override: o.provider
        ? {
            provider: o.provider,
            baseUrl: o.baseUrl ?? null,
            model: o.model ?? null,
            apiKey: maskApiKey(o.apiKey),
          }
        : null,
      persisted: this.runtime.isPersisted(),
    };
  }

  private checkToken(token: string | undefined) {
    const expected = this.config.get<string>('ADMIN_TOKEN');
    if (!expected) throw err.notFound(); // 〔假设〕未配置 ADMIN_TOKEN 时管理端整体关闭
    if (token !== expected) throw err.tokenInvalid();
  }
}
