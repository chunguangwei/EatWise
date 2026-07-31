/**
 * i18n 错误消息字典（D-15）：zh-CN / en 两套，缺省 zh-CN。
 * 按 Accept-Language 请求头选择；客户端只认 error.code，message 可直接上屏。
 */
export type Locale = 'zh-CN' | 'en';

export function resolveLocale(acceptLanguage?: string): Locale {
  if (acceptLanguage && acceptLanguage.toLowerCase().startsWith('en')) return 'en';
  return 'zh-CN';
}

const zh: Record<string, string> = {
  VALIDATION_ERROR: '参数校验失败',
  INVALID_CURSOR: '游标非法或已过期',
  INVALID_SYNC_TOKEN: '同步令牌已失效，请全量重新同步',
  AUTH_TOKEN_EXPIRED: '登录状态已过期，请刷新',
  AUTH_TOKEN_INVALID: '登录状态无效，请重新登录',
  AUTH_REFRESH_REUSED: '检测到令牌异常使用，已全部登出',
  AUTH_CODE_INVALID: '验证码错误或已过期',
  ACCOUNT_DELETED: '账号已注销',
  NOT_FOUND: '资源不存在',
  CONFLICT: '该记录在别处已被修改，请刷新后重试',
  IDEMPOTENCY_PAYLOAD_MISMATCH: '同一请求标识提交了不同内容，请检查客户端',
  RATE_LIMITED: '操作太频繁，请稍后再试',
  INTERNAL_ERROR: '服务开小差了，请稍后重试',
  FASTING_ALREADY_ENDED: '本次断食已经结束',
  FASTING_EXTEND_LIMIT: '今日延长时长已达上限',
  MAKEUP_CARD_EMPTY: '本月补签卡已用完',
  MAKEUP_OUT_OF_WINDOW: '只能补最近 7 天内的断签日',
  MAKEUP_ALREADY_USED: '该日期已经补签过了',
  POST_CONTENT_REJECTED: '内容未通过审核，无法发布',
  RESOURCE_GONE: '该内容已删除',
  ESTIMATE_UNAVAILABLE: '营养估算暂不可用，请手动填写',
};

const en: Record<string, string> = {
  VALIDATION_ERROR: 'Validation failed',
  INVALID_CURSOR: 'Invalid or expired cursor',
  INVALID_SYNC_TOKEN: 'Sync token expired, please re-sync from scratch',
  AUTH_TOKEN_EXPIRED: 'Session expired, please refresh',
  AUTH_TOKEN_INVALID: 'Invalid session, please sign in again',
  AUTH_REFRESH_REUSED: 'Token reuse detected, all sessions signed out',
  AUTH_CODE_INVALID: 'Incorrect or expired verification code',
  ACCOUNT_DELETED: 'Account deleted',
  NOT_FOUND: 'Resource not found',
  CONFLICT: 'This record was modified elsewhere, please refresh and retry',
  IDEMPOTENCY_PAYLOAD_MISMATCH: 'Same request id with different payload',
  RATE_LIMITED: 'Too many requests, please try again later',
  INTERNAL_ERROR: 'Something went wrong, please try again later',
  FASTING_ALREADY_ENDED: 'This fast has already ended',
  FASTING_EXTEND_LIMIT: 'Daily extension limit reached',
  MAKEUP_CARD_EMPTY: 'No makeup cards left this month',
  MAKEUP_OUT_OF_WINDOW: 'Only missed days within the last 7 days can be made up',
  MAKEUP_ALREADY_USED: 'This date has already been made up',
  POST_CONTENT_REJECTED: 'Content did not pass review and cannot be published',
  RESOURCE_GONE: 'This content has been deleted',
  ESTIMATE_UNAVAILABLE: 'Nutrition estimate unavailable, please enter values manually',
};

export function translate(code: string, locale: Locale): string {
  const dict = locale === 'en' ? en : zh;
  return dict[code] ?? dict.INTERNAL_ERROR;
}
