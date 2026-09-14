import { isValidTimezone } from '../src/common/utils/time.util';

/** IANA 时区名合法性（非法名会让 Intl.DateTimeFormat 抛 RangeError 打挂核心端点） */
describe('isValidTimezone', () => {
  it('合法 IANA 名 → true', () => {
    expect(isValidTimezone('Asia/Shanghai')).toBe(true);
    expect(isValidTimezone('UTC')).toBe(true);
    expect(isValidTimezone('Etc/GMT-8')).toBe(true);
    expect(isValidTimezone('America/New_York')).toBe(true);
  });

  it('非法名 / 空串 / 非时区字符串 → false（不抛 RangeError）', () => {
    expect(isValidTimezone('Not/AZone')).toBe(false);
    expect(isValidTimezone('Asia/Beijing')).toBe(false); // 非 IANA 标准名
    expect(isValidTimezone('')).toBe(false);
    expect(isValidTimezone('GMT+8')).toBe(false);
    expect(isValidTimezone('🍕')).toBe(false);
  });
});
