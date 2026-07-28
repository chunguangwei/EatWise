import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from '../src/auth/auth.service';
import { DataStore } from '../src/common/store/data-store';
import { hashToken } from '../src/common/utils/id.util';

describe('AuthService（D-13：验证码登录 + JWT 签发/刷新）', () => {
  let store: DataStore;
  let auth: AuthService;

  beforeEach(() => {
    store = new DataStore();
    auth = new AuthService(
      store,
      new JwtService({ secret: 'test-secret', signOptions: { expiresIn: 7200 } }),
      new ConfigService(),
    );
  });

  const phone = '+8613800138000';

  it('发送验证码返回 ttl 与重发间隔', () => {
    const res = auth.sendSms(phone, 'login');
    expect(res).toEqual({ ttlSec: 300, resendAfterSec: 60 });
  });

  it('60s 内重发返回 429 RATE_LIMITED', () => {
    auth.sendSms(phone, 'login');
    expect(() => auth.sendSms(phone, 'login')).toThrow(
      expect.objectContaining({ code: 'RATE_LIMITED' }) as unknown as Error,
    );
  });

  it('错误验证码返回 AUTH_CODE_INVALID 并递减剩余次数', async () => {
    auth.sendSms(phone, 'login');
    await expect(auth.loginPhone(phone, '000000')).rejects.toMatchObject({
      code: 'AUTH_CODE_INVALID',
      details: { remainingAttempts: 4 },
    });
  });

  it('正确验证码登录：无账号自动注册（isNewUser），签发 access+refresh', async () => {
    auth.sendSms(phone, 'login');
    const res = await auth.loginPhone(phone, '123456', { deviceId: 'd-1', platform: 'ios' });
    expect(res.isNewUser).toBe(true);
    expect(res.accessToken).toBeTruthy();
    expect(res.refreshToken).toMatch(/^rt_/);
    expect(res.expiresIn).toBe(7200);
    expect(res.user.id).toBeTruthy();
  });

  it('同验证码仅可用一次', async () => {
    auth.sendSms(phone, 'login');
    await auth.loginPhone(phone, '123456');
    await expect(auth.loginPhone(phone, '123456')).rejects.toMatchObject({
      code: 'AUTH_CODE_INVALID',
    });
  });

  it('refresh 滑动轮换：旧值重放 → AUTH_REFRESH_REUSED 且全端登出', async () => {
    auth.sendSms(phone, 'login');
    const login = await auth.loginPhone(phone, '123456');

    const rotated = await auth.refresh(login.refreshToken);
    expect(rotated.refreshToken).not.toBe(login.refreshToken);

    // 旧 refreshToken 重放 = 安全事件
    await expect(auth.refresh(login.refreshToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });
    // 全端登出：新 token 也被吊销（已吊销 token 再使用同样按重放处理）
    await expect(auth.refresh(rotated.refreshToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });
    const all = [...store.refreshTokens.values()];
    expect(all.every((t) => t.revokedAt !== null)).toBe(true);
  });

  it('refresh 轮换后旧记录标记 replacedBy', async () => {
    auth.sendSms(phone, 'login');
    const login = await auth.loginPhone(phone, '123456');
    const rotated = await auth.refresh(login.refreshToken);
    const old = store.refreshTokens.get(hashToken(login.refreshToken));
    expect(old?.revokedAt).not.toBeNull();
    expect(old?.replacedBy).toBe(hashToken(rotated.refreshToken));
  });

  it('logout 幂等：重复调用不报错', async () => {
    auth.sendSms(phone, 'login');
    const login = await auth.loginPhone(phone, '123456', { deviceId: 'd-1', platform: 'ios' });
    const userId = store.findUserByPhone(phone)!.id;
    expect(auth.logout(userId, 'd-1')).toEqual({ loggedOut: true });
    expect(auth.logout(userId, 'd-1')).toEqual({ loggedOut: true });
    await expect(auth.refresh(login.refreshToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });
  });
});
