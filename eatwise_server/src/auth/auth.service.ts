import { Inject, Injectable, OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { err } from '../common/errors/business.exception';
import { DataStore, RefreshTokenEntity, UserEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { hashToken, newId, newRefreshToken } from '../common/utils/id.util';
import { PASSWORD_PATTERN, DeviceDto } from './auth.dto';

const SMS_CODE_TTL_SEC = 300;
const SMS_RESEND_AFTER_SEC = 60;
const LOGIN_MAX_ATTEMPTS = 5; // 连续错误 5 次锁 10 分钟〔假设〕
const LOGIN_LOCK_SEC = 600;
const REFRESH_TTL_MS = 30 * 24 * 3600 * 1000; // 30 天〔假设〕
const MAX_DEVICE_SESSIONS = 5; // 最多 5 个活跃设备会话，超出踢最旧〔假设〕

/**
 * 认证（D-13）。用户/会话令牌读写全部收口到 StoreDriver（prisma 模式真实落库）。
 * 〔假设〕短信通道未接入：验证码固定 mock 为 123456 并落内存（DataStore.smsCodes），
 * 由 env SMS_MOCK_ENABLED 开关（默认 true 仅开发用；生产必须 false，此时
 * send-code 与验证码登录一律拒绝 SMS_CHANNEL_UNAVAILABLE）。
 */
@Injectable()
export class AuthService implements OnApplicationBootstrap {
  constructor(
    private readonly store: DataStore,
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  /**
   * 短信 mock 开关：白名单判定——仅显式 'true' 开启（缺省 'true' 保开发/测试；
   * 'False'/'0'/拼错一律关闭，fail-closed，防误配把固定码 123456 通道带上生产）。
   * 生产开启由 onApplicationBootstrap fail-fast 拦截。
   */
  private smsMockEnabled(): boolean {
    return (this.config.get<string>('SMS_MOCK_ENABLED', 'true') ?? 'true') === 'true';
  }

  /** 生产环境 mock 短信（固定码 123456）绝不可用：启动即拒绝，不留运行期侥幸 */
  onApplicationBootstrap() {
    if (
      this.config.get<string>('NODE_ENV') === 'production' &&
      this.smsMockEnabled()
    ) {
      throw new Error(
        'SMS_MOCK_ENABLED must be false when NODE_ENV=production (fixed code 123456 accepts any phone login)',
      );
    }
  }

  sendSms(phone: string, _scene: string) {
    if (!this.smsMockEnabled()) throw err.smsChannelUnavailable();
    const existing = this.store.smsCodes.get(phone);
    if (existing && Date.now() - existing.sentAt.getTime() < SMS_RESEND_AFTER_SEC * 1000) {
      const wait =
        SMS_RESEND_AFTER_SEC - Math.floor((Date.now() - existing.sentAt.getTime()) / 1000);
      throw err.rateLimited(wait);
    }
    // 〔假设〕mock 验证码：固定 123456；生产应为 6 位随机数 + 短信下发
    this.store.smsCodes.set(phone, { code: '123456', sentAt: new Date(), attempts: 0 });
    return { ttlSec: SMS_CODE_TTL_SEC, resendAfterSec: SMS_RESEND_AFTER_SEC };
  }

  async loginPhone(phone: string, code: string, device?: DeviceDto) {
    // 防御：mock 关闭时即便绕过 send-code 直接调登录也拒绝
    if (!this.smsMockEnabled()) throw err.smsChannelUnavailable();
    const record = this.store.smsCodes.get(phone);
    if (!record || Date.now() - record.sentAt.getTime() > SMS_CODE_TTL_SEC * 1000) {
      throw err.authCodeInvalid(0);
    }
    if (record.attempts >= LOGIN_MAX_ATTEMPTS) throw err.rateLimited(LOGIN_LOCK_SEC);
    if (record.code !== code) {
      record.attempts += 1;
      throw err.authCodeInvalid(Math.max(0, LOGIN_MAX_ATTEMPTS - record.attempts));
    }
    this.store.smsCodes.delete(phone); // 同验证码仅可用一次

    let isNewUser = false;
    let deletionCancelled = false;
    let user = await this.driver.findUserByPhone(phone);
    if (!user) {
      user = await this.driver.createUser({ phone });
      isNewUser = true;
    } else if (user.deletionStatus === 'pending') {
      // 合规 §4.3：7 天冷静期内登录即视为撤销注销，并明示告知（deletionCancelled）
      user = await this.driver.updateUserDeletion(user.id, null, null);
      deletionCancelled = true;
    }
    const tokens = await this.issueTokens(user, device?.deviceId ?? null);
    return { ...tokens, isNewUser, deletionCancelled, user: this.publicUser(user) };
  }

  async refresh(refreshToken: string, deviceId?: string | null) {
    const hash = hashToken(refreshToken);
    const record = await this.driver.findRefreshTokenByHash(hash);
    if (!record) throw err.tokenInvalid();
    // Reuse Detection：已轮换/吊销的旧值重放 = 安全事件 → 全端登出（契约 §1.2）
    if (record.revokedAt) {
      await this.revokeAllUserTokens(record.userId);
      throw err.refreshReused();
    }
    if (record.expiresAt.getTime() < Date.now()) throw err.tokenInvalid();

    const user = await this.driver.findUserById(record.userId);
    if (!user || user.deletedAt) throw err.tokenInvalid();

    const tokens = await this.issueTokens(user, deviceId ?? record.deviceId);
    // 旧记录标记已轮换：revokedAt + replacedBy（指向新令牌哈希）
    await this.driver.rotateRefreshToken(hash, hashToken(tokens.refreshToken));
    return { ...tokens, isNewUser: false, user: this.publicUser(user) };
  }

  async logout(userId: string, deviceId?: string) {
    await this.driver.revokeUserRefreshTokens(userId, deviceId);
    return { loggedOut: true };
  }

  /**
   * 账号密码注册（D-13 修订主路径）。用户名唯一（大小写不敏感，存储小写归一化）；
   * 密码策略在服务端最终判定（AUTH_PASSWORD_TOO_WEAK），哈希后存储永不返回。
   */
  async register(username: string, password: string, device?: DeviceDto) {
    if (!PASSWORD_PATTERN.test(password)) throw err.passwordTooWeak();
    const name = username.trim().toLowerCase();
    if (await this.driver.findUserByUsername(name)) throw err.usernameTaken();
    const user = await this.driver.createUser({
      username: name,
      passwordHash: await bcrypt.hash(password, 10),
    });
    const tokens = await this.issueTokens(user, device?.deviceId ?? null);
    return { ...tokens, isNewUser: true, deletionCancelled: false, user: this.publicUser(user) };
  }

  /**
   * 账号密码登录。用户名不存在 / 无密码（纯手机号账号）/ 密码错误 一律
   * AUTH_INVALID_CREDENTIALS，不泄露账号存在性（防枚举）。
   */
  async login(username: string, password: string, device?: DeviceDto) {
    let user = await this.driver.findUserByUsername(username);
    if (!user || !user.passwordHash || !(await bcrypt.compare(password, user.passwordHash))) {
      throw err.invalidCredentials();
    }
    let deletionCancelled = false;
    if (user.deletionStatus === 'pending') {
      // 合规 §4.3：冷静期内登录即撤销注销并明示告知（同 loginPhone）
      user = await this.driver.updateUserDeletion(user.id, null, null);
      deletionCancelled = true;
    }
    const tokens = await this.issueTokens(user, device?.deviceId ?? null);
    return { ...tokens, isNewUser: false, deletionCancelled, user: this.publicUser(user) };
  }

  /**
   * 修改密码（需认证）。旧密码不符 → AUTH_INVALID_CREDENTIALS；
   * 成功后吊销该用户全部 refresh token（全端强制重新登录）。
   * accessToken 无状态，在有效期内仍可用，下一次 refresh 起失效。
   */
  async changePassword(userId: string, oldPassword: string, newPassword: string) {
    const user = await this.driver.findUserById(userId);
    if (!user || user.deletedAt || !user.passwordHash) throw err.invalidCredentials();
    if (!(await bcrypt.compare(oldPassword, user.passwordHash))) throw err.invalidCredentials();
    if (!PASSWORD_PATTERN.test(newPassword)) throw err.passwordTooWeak();
    await this.driver.updateUserPasswordHash(userId, await bcrypt.hash(newPassword, 10));
    await this.revokeAllUserTokens(userId);
    return { changed: true };
  }

  private async issueTokens(user: UserEntity, deviceId: string | null) {
    const accessToken = await this.jwt.signAsync({ sub: user.id });
    const refreshToken = newRefreshToken();
    const now = new Date();
    const entity: RefreshTokenEntity = {
      id: newId(),
      userId: user.id,
      tokenHash: hashToken(refreshToken),
      deviceId,
      expiresAt: new Date(now.getTime() + REFRESH_TTL_MS),
      revokedAt: null,
      replacedBy: null,
      createdAt: now,
    };
    await this.driver.createRefreshToken(entity);
    await this.enforceSessionLimit(user.id);
    return {
      accessToken,
      refreshToken,
      expiresIn: Number(this.config.get('JWT_ACCESS_TTL_SEC', 7200)),
    };
  }

  /** 多端登录：同一用户最多 5 个活跃设备会话，超出踢最旧〔假设〕 */
  private async enforceSessionLimit(userId: string) {
    const active = await this.driver.listActiveRefreshTokens(userId);
    for (const t of active.slice(0, Math.max(0, active.length - MAX_DEVICE_SESSIONS))) {
      await this.driver.revokeRefreshToken(t.tokenHash);
    }
  }

  private async revokeAllUserTokens(userId: string) {
    await this.driver.revokeUserRefreshTokens(userId);
  }

  private publicUser(user: UserEntity) {
    return {
      id: user.id,
      nickname: user.nickname,
      locale: user.locale,
      timezone: user.timezone,
      goal: user.goal,
      onboardingStatus: user.onboardingStatus,
    };
  }
}
