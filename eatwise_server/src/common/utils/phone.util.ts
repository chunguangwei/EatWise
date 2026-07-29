/**
 * 手机号脱敏（合规 §6 日志/响应脱敏）：U1 userView 等对外响应不返回明文手机号。
 * 中国大陆 E.164（+86 + 11 位）→ `138****8000`；其他号码保底「前 3 + **** + 后 4」。
 */
export function maskPhone(phone: string | null): string | null {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, '');
  const national = digits.startsWith('86') && digits.length === 13 ? digits.slice(2) : digits;
  if (national.length === 11) return `${national.slice(0, 3)}****${national.slice(7)}`;
  if (national.length > 7) return `${national.slice(0, 3)}****${national.slice(-4)}`;
  return '****';
}
