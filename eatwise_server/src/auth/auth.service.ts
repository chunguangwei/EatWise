import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { err } from '../common/errors/business.exception';
import { DataStore, RefreshTokenEntity, UserEntity } from '../common/store/data-store';
import { hashToken, newId, newRefreshToken } from '../common/utils/id.util';
import { PASSWORD_PATTERN, DeviceDto } from './auth.dto';

const SMS_CODE_TTL_SEC = 300;
const SMS_RESEND_AFTER_SEC = 60;
const LOGIN_MAX_ATTEMPTS = 5; // 连续错误 5 次锁 10 分钟〔假设〕
const LOGIN_LOCK_SEC = 600;
const REFRESH_TTL_MS = 30 * 24 * 3600 * 1000; // 30 天〔假设〕
const MAX_DEVICE_SESSIONS = 5; // 最多 5 个活跃设备会话，超出踢最旧〔假设〕

/**
 * 认证（D-13）。〔假设〕短信通道未接入：验证码固定 mock 为 123456 并落内存，
 * 生产实现应替换为真实短信服务商 + Redis 存储。
 */
@Injectable()
export class AuthService {
  constructor(
    private readonly store: DataStore,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  sendSms(phone: string, _scene: string) {
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
    let user = this.store.findUserByPhone(phone);
    if (!user) {
      user = this.store.createUser({ phone });
      isNewUser = true;
    } else if (user.deletionStatus === 'pending') {
      // 合规 §4.3：7 天冷静期内登录即视为撤销注销，并明示告知（deletionCancelled）
      user.deletionStatus = null;
      user.scheduledDeletionAt = null;
      user.version += 1;
      user.updatedAt = new Date();
      deletionCancelled = true;
    }
    const tokens = await this.issueTokens(user, device?.deviceId ?? null);
    return { ...tokens, isNewUser, deletionCancelled, user: this.publicUser(user) };
  }

  async refresh(refreshToken: string, deviceId?: string | null) {
    const hash = hashToken(refreshToken);
    const record = this.store.refreshTokens.get(hash);
    if (!record) throw err.tokenInvalid();
    // Reuse Detection：已轮换/吊销的旧值重放 = 安全事件 → 全端登出（契约 §1.2）
    if (record.revokedAt) {
      this.revokeAllUserTokens(record.userId);
      throw err.refreshReused();
    }
    if (record.expiresAt.getTime() < Date.now()) throw err.tokenInvalid();

    const user = this.store.users.get(record.userId);
    if (!user || user.deletedAt) throw err.tokenInvalid();

    const tokens = await this.issueTokens(user, deviceId ?? record.deviceId);
    record.revokedAt = new Date();
    record.replacedBy = hashToken(tokens.refreshToken);
    return { ...tokens, isNewUser: false, user: this.publicUser(user) };
  }

  logout(userId: string, deviceId?: string) {
    for (const t of this.store.refreshTokens.values()) {
      if (t.userId === userId && !t.revokedAt && (!deviceId || t.deviceId === deviceId)) {
        t.revokedAt = new Date();
      }
    }
    return { loggedOut: true };
  }

  /**
   * 账号密码注册（D-13 修订主路径）。用户名唯一（大小写不敏感，存储小写归一化）；
   * 密码策略在服务端最终判定（AUTH_PASSWORD_TOO_WEAK），哈希后存储永不返回。
   */
  async register(username: string, password: string, device?: DeviceDto) {
    if (!PASSWORD_PATTERN.test(password)) throw err.passwordTooWeak();
    const name = username.trim().toLowerCase();
    if (this.store.findUserByUsername(name)) throw err.usernameTaken();
    const user = this.store.createUser({
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
    const user = this.store.findUserByUsername(username);
    if (!user || !user.passwordHash || !(await bcrypt.compare(password, user.passwordHash))) {
      throw err.invalidCredentials();
    }
    let deletionCancelled = false;
    if (user.deletionStatus === 'pending') {
      // 合规 §4.3：冷静期内登录即撤销注销并明示告知（同 loginPhone）
      user.deletionStatus = null;
      user.scheduledDeletionAt = null;
      user.version += 1;
      user.updatedAt = new Date();
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
    const user = this.store.users.get(userId);
    if (!user || user.deletedAt || !user.passwordHash) throw err.invalidCredentials();
    if (!(await bcrypt.compare(oldPassword, user.passwordHash))) throw err.invalidCredentials();
    if (!PASSWORD_PATTERN.test(newPassword)) throw err.passwordTooWeak();
    user.passwordHash = await bcrypt.hash(newPassword, 10);
    user.version += 1;
    user.updatedAt = new Date();
    this.revokeAllUserTokens(userId);
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
    this.store.refreshTokens.set(entity.tokenHash, entity);
    this.enforceSessionLimit(user.id);
    return {
      accessToken,
      refreshToken,
      expiresIn: Number(this.config.get('JWT_ACCESS_TTL_SEC', 7200)),
    };
  }

  /** 多端登录：同一用户最多 5 个活跃设备会话，超出踢最旧〔假设〕 */
  private enforceSessionLimit(userId: string) {
    const active = [...this.store.refreshTokens.values()]
      .filter((t) => t.userId === userId && !t.revokedAt && t.expiresAt.getTime() > Date.now())
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
    for (const t of active.slice(0, Math.max(0, active.length - MAX_DEVICE_SESSIONS))) {
      t.revokedAt = new Date();
    }
  }

  private revokeAllUserTokens(userId: string) {
    for (const t of this.store.refreshTokens.values()) {
      if (t.userId === userId && !t.revokedAt) t.revokedAt = new Date();
    }
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
