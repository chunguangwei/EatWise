/**
 * 时区 / UTC 工具（D-07）：
 * - 所有时间戳 UTC 存储、UTC 传输（ISO 8601 毫秒）
 * - 本地自然日概念一律经 X-Timezone（IANA 名称）换算
 * - 归属日 = 进食窗口所属自然日，由服务端统一计算
 */

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

export function isValidDateStr(s: string): boolean {
  return DATE_RE.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00.000Z`));
}

export function isValidTimeStr(s: string): boolean {
  return TIME_RE.test(s);
}

/** IANA 时区名合法性（Intl 判定；非法名会让 DateTimeFormat 抛 RangeError 打挂请求） */
export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

function tzParts(tz: string, at: Date): Record<string, number> {
  const dtf = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const out: Record<string, number> = {};
  for (const p of dtf.formatToParts(at)) {
    if (p.type !== 'literal') out[p.type] = parseInt(p.value, 10);
  }
  return out;
}

/** UTC 时刻在 tz 下的本地自然日，YYYY-MM-DD */
export function localDateOf(at: Date, tz: string): string {
  const p = tzParts(tz, at);
  const mm = String(p.month).padStart(2, '0');
  const dd = String(p.day).padStart(2, '0');
  return `${p.year}-${mm}-${dd}`;
}

/** UTC 时刻在 tz 下的本地月份，YYYY-MM */
export function localMonthOf(at: Date, tz: string): string {
  const p = tzParts(tz, at);
  return `${p.year}-${String(p.month).padStart(2, '0')}`;
}

/** tz 在 at 时刻相对 UTC 的偏移（毫秒） */
function tzOffsetMs(tz: string, at: Date): number {
  const p = tzParts(tz, at);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute, p.second);
  return asUtc - Math.floor(at.getTime() / 1000) * 1000;
}

/** 本地日 + 本地时刻（HH:mm）+ IANA 时区 → UTC Date */
export function zonedTimeToUtc(dateStr: string, timeStr: string, tz: string): Date {
  const guess = new Date(`${dateStr}T${timeStr}:00.000Z`);
  return new Date(guess.getTime() - tzOffsetMs(tz, guess));
}

/** 本地日字符串加减天数 */
export function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** ISO 8601 毫秒格式（UTC） */
export function toIso(d: Date): string {
  return d.toISOString();
}
