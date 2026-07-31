import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { isPer100gInRange } from '../food/food.rules';
import {
  EstimateConfidence,
  LLM_ESTIMATE_PROVIDER,
  LlmEstimateProvider,
  Per100g,
} from './llm-estimate.types';

/** 〔假设〕估算结果缓存 30 天：菜名营养值稳定，避免重复计费 */
export const ESTIMATE_CACHE_TTL_MS = 30 * 24 * 3600 * 1000;

export interface EstimateResult {
  name: string;
  per100g: Per100g;
  confidence: EstimateConfidence;
  source: 'llm-estimate';
  cached: boolean;
}

interface CacheEntry {
  per100g: Per100g;
  confidence: EstimateConfidence;
  expiresAt: number;
}

@Injectable()
export class EstimateService {
  /** key = provider|model|规范化菜名（trim+小写） */
  private readonly cache = new Map<string, CacheEntry>();

  constructor(@Inject(LLM_ESTIMATE_PROVIDER) private readonly provider: LlmEstimateProvider) {}

  async estimate(rawName: string, description?: string): Promise<EstimateResult> {
    const name = (rawName ?? '').trim();
    if (name.length < 1 || name.length > 50) {
      throw err.validation({ name: 'trimmed length must be 1-50' });
    }

    const key = `${this.provider.name}|${this.provider.model ?? ''}|${name.toLowerCase()}`;
    const hit = this.cache.get(key);
    if (hit) {
      if (hit.expiresAt > Date.now()) {
        return {
          name,
          per100g: hit.per100g,
          confidence: hit.confidence,
          source: 'llm-estimate',
          cached: true,
        };
      }
      this.cache.delete(key);
    }

    const est = await this.provider.estimate(name, description);
    // 越界营养值拒绝（视为不可用输出，不落缓存）
    if (!isPer100gInRange(est.per100g)) throw err.estimateUnavailable();

    this.cache.set(key, {
      per100g: est.per100g,
      confidence: est.confidence,
      expiresAt: Date.now() + ESTIMATE_CACHE_TTL_MS,
    });
    return {
      name,
      per100g: est.per100g,
      confidence: est.confidence,
      source: 'llm-estimate',
      cached: false,
    };
  }
}
