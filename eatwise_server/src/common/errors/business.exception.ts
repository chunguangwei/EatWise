import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * 业务异常：稳定机器可读码（SCREAMING_SNAKE）+ HTTP 状态 + 结构化 details。
 * message 由全局异常过滤器按 Accept-Language 从 i18n 字典渲染（D-15），
 * 客户端分支判断只认 code，不认 message。
 */
export class BusinessException extends HttpException {
  constructor(
    public readonly code: string,
    status: HttpStatus,
    public readonly details?: Record<string, unknown>,
  ) {
    super(code, status);
  }
}

// 通用错误码（契约 §1.8）
export const err = {
  validation: (fields?: Record<string, string>) =>
    new BusinessException(
      'VALIDATION_ERROR',
      HttpStatus.BAD_REQUEST,
      fields ? { fields } : undefined,
    ),
  invalidCursor: () => new BusinessException('INVALID_CURSOR', HttpStatus.BAD_REQUEST),
  invalidSyncToken: () => new BusinessException('INVALID_SYNC_TOKEN', HttpStatus.BAD_REQUEST),
  tokenExpired: () => new BusinessException('AUTH_TOKEN_EXPIRED', HttpStatus.UNAUTHORIZED),
  tokenInvalid: () => new BusinessException('AUTH_TOKEN_INVALID', HttpStatus.UNAUTHORIZED),
  refreshReused: () => new BusinessException('AUTH_REFRESH_REUSED', HttpStatus.UNAUTHORIZED),
  notFound: () => new BusinessException('NOT_FOUND', HttpStatus.NOT_FOUND),
  conflict: (details?: Record<string, unknown>) =>
    new BusinessException('CONFLICT', HttpStatus.CONFLICT, details),
  payloadMismatch: () => new BusinessException('IDEMPOTENCY_PAYLOAD_MISMATCH', HttpStatus.CONFLICT),
  rateLimited: (retryAfterSec = 60) =>
    new BusinessException('RATE_LIMITED', HttpStatus.TOO_MANY_REQUESTS, { retryAfterSec }),
  internal: () => new BusinessException('INTERNAL_ERROR', HttpStatus.INTERNAL_SERVER_ERROR),

  // 认证
  authCodeInvalid: (remainingAttempts?: number) =>
    new BusinessException('AUTH_CODE_INVALID', HttpStatus.BAD_REQUEST, { remainingAttempts }),

  // 断食
  fastingAlreadyEnded: () => new BusinessException('FASTING_ALREADY_ENDED', HttpStatus.CONFLICT),
  fastingExtendLimit: (extendRemainingMinutes: number) =>
    new BusinessException('FASTING_EXTEND_LIMIT', HttpStatus.BAD_REQUEST, {
      extendRemainingMinutes,
    }),

  // 补签卡（D-12）
  makeupCardEmpty: () => new BusinessException('MAKEUP_CARD_EMPTY', HttpStatus.BAD_REQUEST),
  makeupOutOfWindow: () => new BusinessException('MAKEUP_OUT_OF_WINDOW', HttpStatus.BAD_REQUEST),
  makeupAlreadyUsed: () => new BusinessException('MAKEUP_ALREADY_USED', HttpStatus.CONFLICT),

  // LLM 营养估算（供应商未配置/超时/输出非法时，客户端降级手动填写）
  estimateUnavailable: () =>
    new BusinessException('ESTIMATE_UNAVAILABLE', HttpStatus.SERVICE_UNAVAILABLE),

  // 社区打卡（M5 / D-17 先审后发）
  postContentRejected: (reason?: { zh: string; en: string }) =>
    new BusinessException('POST_CONTENT_REJECTED', HttpStatus.BAD_REQUEST, { reason }),
  resourceGone: () => new BusinessException('RESOURCE_GONE', HttpStatus.GONE),
};
