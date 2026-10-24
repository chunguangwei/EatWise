import { isValidDateStr } from '../src/common/utils/time.util';

describe('isValidDateStr', () => {
  it.each(['2028-02-29', '2026-02-28', '2026-12-31'])('接受真实日期 %s', (date) => {
    expect(isValidDateStr(date)).toBe(true);
  });

  it.each(['2026-02-29', '2026-04-31', '2026-13-01', '2026-00-10', '2026/02/28'])(
    '拒绝格式正确但不存在的日期或错误格式 %s',
    (date) => {
      expect(isValidDateStr(date)).toBe(false);
    },
  );
});
