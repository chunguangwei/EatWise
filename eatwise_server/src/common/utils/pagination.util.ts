import { err } from '../errors/business.exception';

/**
 * 分页 limit 归一化：非法值（NaN / 负数 / 小数 / 0）回落默认值，封顶 max。
 * 负数/NaN limit 会绕过页上限并造成游标死循环（hasMore 恒真），必须在入口收口。
 */
export function clampPageLimit(limit: number, fallback: number, max: number): number {
  if (!Number.isFinite(limit) || limit < 1) return fallback;
  return Math.min(max, Math.floor(limit));
}

/** offset 游标解析（{offset} base64 JSON）：必须为非负整数，否则 400 INVALID_CURSOR */
export function parseOffsetCursor(cursor: string): number {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8'));
    const offset = (parsed as { offset?: unknown } | null)?.offset ?? 0;
    if (typeof offset !== 'number' || !Number.isInteger(offset) || offset < 0) {
      throw new Error('bad offset');
    }
    return offset;
  } catch {
    throw err.invalidCursor();
  }
}
