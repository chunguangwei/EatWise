import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { LlmEstimate, LlmEstimateProvider } from './llm-estimate.types';

/**
 * 未配置 LLM 供应商时的默认实现：直接抛 ESTIMATE_UNAVAILABLE，
 * 客户端据此降级为手动填写（产品决策）。
 */
@Injectable()
export class StubProvider implements LlmEstimateProvider {
  readonly name = 'stub';

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async estimate(_name: string, _description?: string): Promise<LlmEstimate> {
    throw err.estimateUnavailable();
  }
}
