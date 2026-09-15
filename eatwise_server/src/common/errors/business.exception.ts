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
  /** 已认证但角色权限不足（如 reviewer 调 admin-only 端点） */
  forbidden: () => new BusinessException('FORBIDDEN', HttpStatus.FORBIDDEN),
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

  // 账号密码认证（D-13 修订：账号密码为主路径）
  /** 注册用户名已被占用 */
  usernameTaken: () => new BusinessException('AUTH_USERNAME_TAKEN', HttpStatus.CONFLICT),
  /** 用户名不存在 / 密码错误 / 改密旧密码错误：同一码不泄露账号存在性（防枚举） */
  invalidCredentials: () =>
    new BusinessException('AUTH_INVALID_CREDENTIALS', HttpStatus.UNAUTHORIZED),
  /** 密码不满足强度策略（8-64 且同时含字母和数字） */
  passwordTooWeak: () => new BusinessException('AUTH_PASSWORD_TOO_WEAK', HttpStatus.BAD_REQUEST),

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

  // 条码查询（OFF 无该商品/超时/数据缺字段，客户端降级手动搜索/自定义食物）
  barcodeNotFound: () => new BusinessException('FOOD_BARCODE_NOT_FOUND', HttpStatus.NOT_FOUND),

  // 众包食物贡献（食物名机审 rejected → 贡献直接拒收，D-17 先审后发）
  foodContributeRejected: (reason?: { zh: string; en: string }) =>
    new BusinessException('FOOD_CONTRIBUTE_REJECTED', HttpStatus.BAD_REQUEST, { reason }),

  // 社区打卡（M5 / D-17 先审后发）
  postContentRejected: (reason?: { zh: string; en: string }) =>
    new BusinessException('POST_CONTENT_REJECTED', HttpStatus.BAD_REQUEST, { reason }),
  resourceGone: () => new BusinessException('RESOURCE_GONE', HttpStatus.GONE),

  // 图片上传（打卡配图）
  uploadTypeUnsupported: () =>
    new BusinessException('UPLOAD_TYPE_UNSUPPORTED', HttpStatus.UNSUPPORTED_MEDIA_TYPE),
  uploadTooLarge: () =>
    new BusinessException('UPLOAD_FILE_TOO_LARGE', HttpStatus.PAYLOAD_TOO_LARGE),
};
