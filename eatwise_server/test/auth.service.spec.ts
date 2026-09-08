import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from '../src/auth/auth.service';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { hashToken } from '../src/common/utils/id.util';

describe('AuthService（D-13：验证码/账号密码登录 + JWT 签发/刷新）', () => {
  let store: DataStore;
  let auth: AuthService;

  beforeEach(() => {
    store = new DataStore();
    auth = new AuthService(
      store,
      new MemoryStoreDriver(store),
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
    expect(await auth.logout(userId, 'd-1')).toEqual({ loggedOut: true });
    expect(await auth.logout(userId, 'd-1')).toEqual({ loggedOut: true });
    await expect(auth.refresh(login.refreshToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });
  });
});

describe('AuthService 账号密码认证（D-13 修订主路径：注册/登录/改密）', () => {
  let store: DataStore;
  let auth: AuthService;

  beforeEach(() => {
    store = new DataStore();
    auth = new AuthService(
      store,
      new MemoryStoreDriver(store),
      new JwtService({ secret: 'test-secret', signOptions: { expiresIn: 7200 } }),
      new ConfigService(),
    );
  });

  const username = 'Alice_01';
  const password = 'Passw0rd123';

  it('register 成功：签发 access+refresh，isNewUser=true，用户名小写归一化', async () => {
    const res = await auth.register(username, password, { deviceId: 'd-9', platform: 'android' });
    expect(res.isNewUser).toBe(true);
    expect(res.deletionCancelled).toBe(false);
    expect(res.accessToken).toBeTruthy();
    expect(res.refreshToken).toMatch(/^rt_/);
    expect(res.expiresIn).toBe(7200);
    expect(res.user.id).toBeTruthy();
    const stored = store.findUserByUsername('alice_01');
    expect(stored?.username).toBe('alice_01');
    expect(stored?.passwordHash).not.toBe(password); // 永不明文
  });

  it('register 用户名重复（大小写不敏感）→ AUTH_USERNAME_TAKEN', async () => {
    await auth.register(username, password);
    await expect(auth.register('ALICE_01', 'Other1234')).rejects.toMatchObject({
      code: 'AUTH_USERNAME_TAKEN',
    });
  });

  it('register 密码太弱（无数字）→ AUTH_PASSWORD_TOO_WEAK', async () => {
    await expect(auth.register('bob_42', 'onlyletters')).rejects.toMatchObject({
      code: 'AUTH_PASSWORD_TOO_WEAK',
    });
    expect(store.findUserByUsername('bob_42')).toBeUndefined(); // 校验失败不落库
  });

  it('login 成功：isNewUser=false，可携带 device', async () => {
    await auth.register(username, password);
    const res = await auth.login('alice_01', password, { deviceId: 'd-1', platform: 'ios' });
    expect(res.isNewUser).toBe(false);
    expect(res.deletionCancelled).toBe(false);
    expect(res.accessToken).toBeTruthy();
  });

  it('login 冷静期内登录撤销注销并返回 deletionCancelled', async () => {
    const reg = await auth.register(username, password);
    const user = store.users.get(reg.user.id)!;
    user.deletionStatus = 'pending';
    user.scheduledDeletionAt = new Date(Date.now() + 7 * 24 * 3600 * 1000);
    const res = await auth.login(username, password);
    expect(res.deletionCancelled).toBe(true);
    expect(user.deletionStatus).toBeNull();
  });

  it('login 用户名不存在 → AUTH_INVALID_CREDENTIALS（防枚举）', async () => {
    await expect(auth.login('ghost_99', password)).rejects.toMatchObject({
      code: 'AUTH_INVALID_CREDENTIALS',
    });
  });

  it('login 密码错误 → AUTH_INVALID_CREDENTIALS（与用户名不存在同码）', async () => {
    await auth.register(username, password);
    await expect(auth.login('alice_01', 'Wrong12345')).rejects.toMatchObject({
      code: 'AUTH_INVALID_CREDENTIALS',
    });
  });

  it('changePassword 成功：新密码可登录、旧密码失效、全部 refresh token 吊销', async () => {
    const reg = await auth.register(username, password);
    await auth.login(username, password, { deviceId: 'd-2', platform: 'ios' });
    const res = await auth.changePassword(reg.user.id, password, 'N3wPassword');
    expect(res).toEqual({ changed: true });
    // 改密即全端吊销：此时库内全部 refresh token 均已 revoked
    const all = [...store.refreshTokens.values()];
    expect(all.length).toBeGreaterThan(0);
    expect(all.every((t) => t.revokedAt !== null)).toBe(true);
    await expect(auth.login(username, password)).rejects.toMatchObject({
      code: 'AUTH_INVALID_CREDENTIALS',
    });
    await expect(auth.login(username, 'N3wPassword')).resolves.toMatchObject({
      isNewUser: false,
    });
    // 改密前签发的 refresh token 已吊销：重放走复用检测（同 logout 语义）→ 全端登出
    await expect(auth.refresh(reg.refreshToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_REUSED',
    });
  });

  it('changePassword 旧密码错误 → AUTH_INVALID_CREDENTIALS 且不改哈希', async () => {
    const reg = await auth.register(username, password);
    const before = store.users.get(reg.user.id)!.passwordHash;
    await expect(
      auth.changePassword(reg.user.id, 'Wrong12345', 'N3wPassword'),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
    expect(store.users.get(reg.user.id)!.passwordHash).toBe(before);
  });

  it('changePassword 新密码太弱（纯数字）→ AUTH_PASSWORD_TOO_WEAK 且不吊销', async () => {
    const reg = await auth.register(username, password);
    await expect(auth.changePassword(reg.user.id, password, '12345678')).rejects.toMatchObject({
      code: 'AUTH_PASSWORD_TOO_WEAK',
    });
    await expect(auth.refresh(reg.refreshToken)).resolves.toMatchObject({ isNewUser: false });
  });

  it('changePassword 纯手机号账号（无 passwordHash）→ AUTH_INVALID_CREDENTIALS', async () => {
    const phoneUser = store.createUser({ phone: '+8613800138000' });
    await expect(
      auth.changePassword(phoneUser.id, 'Whatever123', 'N3wPassword'),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
  });
});
