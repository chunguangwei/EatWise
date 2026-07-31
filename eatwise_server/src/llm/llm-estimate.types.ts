/**
 * LLM 营养估算 Provider 抽象（供应商可插拔）。
 * 产品决策：估算结果只作「估算」标记值展示，不写入权威食物库；供应商 key 仅服务端配置。
 */

export interface Per100g {
  kcal: number;
  proteinG: number;
  carbG: number;
  fatG: number;
}

export type EstimateConfidence = 'high' | 'medium' | 'low';

export interface LlmEstimate {
  per100g: Per100g;
  confidence: EstimateConfidence;
  /** 原始输出（调试用，不随端点响应下发） */
  rawText?: string;
}

export const LLM_ESTIMATE_PROVIDER = Symbol('LLM_ESTIMATE_PROVIDER');

export interface LlmEstimateProvider {
  /** 供应商标识（缓存 key 组成部分，stub/deepseek/qwen/kimi/custom） */
  readonly name: string;
  /** 模型名（缓存 key 组成部分；stub 无模型） */
  readonly model?: string;
  estimate(name: string, description?: string): Promise<LlmEstimate>;
}
