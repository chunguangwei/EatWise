import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { err } from '../common/errors/business.exception';
import { AdminUserEntity, DataStore } from '../common/store/data-store';

export const ADMIN_JWT_TTL_SEC = 12 * 3600; // 12h〔假设〕

const LOGIN_WINDOW_MS = 60_000;
const LOGIN_MAX_PER_WINDOW = 5; // 同一用户名 5 次/分钟〔假设〕

/** 管理员 JWT payload（与用户 JWT 完全独立：独立 secret + role 声明） */
export interface AdminJwtPayload {
  sub: string;
  username: string;
  role: 'admin' | 'reviewer';
}

/**
 * 管理员账号体系（管理控制台登录 + 角色；与用户体系完全独立）。
 * 种子：启动时 adminUsers 为空且 env ADMIN_USERNAME/ADMIN_PASSWORD 齐备 → 创建 admin 账号；
 * 都未配置时不创建任何账号，仅 x-admin-token 兜底可用（过渡方案，见 .env.example）。
 */
@Injectable()
export class AdminAuthService implements OnApplicationBootstrap {
  private readonly logger = new Logger(AdminAuthService.name);
  /** 登录限流滑动窗口（内存实现〔假设〕；多实例部署应换 Redis） */
  private readonly loginAttempts = new Map<string, number[]>();

  constructor(
    private readonly store: DataStore,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async onApplicationBootstrap() {
    await this.seedInitialAdmin();
  }

  /** 管理员 JWT 独立 secret：缺省由 JWT_SECRET 派生〔假设〕，生产建议显式配置 */
  jwtSecret(): string {
    return (
      this.config.get<string>('ADMIN_JWT_SECRET') ??
      `${this.config.get<string>('JWT_SECRET', 'eatwise-dev-secret')}:admin`
    );
  }

  private async seedInitialAdmin() {
    if (this.store.adminUsers.size > 0) return;
    const username = this.config.get<string>('ADMIN_USERNAME')?.trim();
    const password = this.config.get<string>('ADMIN_PASSWORD');
    if (!username || !password) return;
    this.store.createAdminUser({
      username,
      passwordHash: await bcrypt.hash(password, 10),
      role: 'admin',
      disabled: false,
    });
    this.logger.log(`已创建初始管理员账号：${username}（role=admin）`);
  }

  private checkRateLimit(username: string) {
    const key = username.trim().toLowerCase();
    const now = Date.now();
    const recent = (this.loginAttempts.get(key) ?? []).filter((t) => now - t < LOGIN_WINDOW_MS);
    if (recent.length >= LOGIN_MAX_PER_WINDOW) {
      const retryAfterSec = Math.ceil((LOGIN_WINDOW_MS - (now - recent[0])) / 1000);
      throw err.rateLimited(Math.max(1, retryAfterSec));
    }
    recent.push(now);
    this.loginAttempts.set(key, recent);
  }

  async login(username: string, password: string) {
    this.checkRateLimit(username);
    const admin = this.store.findAdminByUsername(username);
    // 用户不存在 / 密码错误 / 已禁用 一律报同一错误码，不泄露账号是否存在
    if (!admin || admin.disabled || !(await bcrypt.compare(password, admin.passwordHash))) {
      throw err.tokenInvalid();
    }
    const accessToken = await this.signAdminToken(admin);
    return { accessToken, expiresIn: ADMIN_JWT_TTL_SEC, admin: this.publicAdmin(admin) };
  }

  async signAdminToken(admin: AdminUserEntity): Promise<string> {
    const payload: AdminJwtPayload = { sub: admin.id, username: admin.username, role: admin.role };
    return this.jwt.signAsync(payload, {
      secret: this.jwtSecret(),
      expiresIn: ADMIN_JWT_TTL_SEC,
    });
  }

  /** 校验管理员 JWT：签名/过期 + 账号仍存在且未禁用（禁用即刻失效） */
  async verifyAdminToken(token: string): Promise<AdminUserEntity> {
    let payload: AdminJwtPayload;
    try {
      payload = await this.jwt.verifyAsync<AdminJwtPayload>(token, { secret: this.jwtSecret() });
    } catch (e) {
      if ((e as Error).name === 'TokenExpiredError') throw err.tokenExpired();
      throw err.tokenInvalid();
    }
    const admin = this.store.adminUsers.get(payload.sub);
    if (!admin || admin.disabled || admin.username !== payload.username) throw err.tokenInvalid();
    return admin;
  }

  publicAdmin(admin: AdminUserEntity) {
    return {
      id: admin.id,
      username: admin.username,
      role: admin.role,
      createdAt: admin.createdAt,
    };
  }
}
