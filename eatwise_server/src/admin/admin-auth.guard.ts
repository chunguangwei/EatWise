import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { err } from '../common/errors/business.exception';
import { AdminRoleName, AdminUserEntity } from '../common/store/data-store';
import { AdminAuthService } from './admin-auth.service';
import { ADMIN_ROLE_KEY, roleSatisfies } from './admin-role.decorator';

/** 认证通过后挂在 req.adminUser 上的上下文（x-admin-token 兜底视为 admin） */
export interface AdminRequestContext {
  id: string | null; // x-admin-token 兜底为 null
  username: string; // x-admin-token 兜底为 'token'
  role: AdminRoleName;
}

/**
 * 管理端守卫（与用户 JWT 体系完全独立，配合 @Public() 使用）：
 * 1. Authorization: Bearer <adminJwt>（POST /v1/admin/auth/login 签发，12h）
 * 2. x-admin-token 兜底（过渡兼容方案，视为 admin 角色；env ADMIN_TOKEN 未配置时不可用）
 * 角色门槛经 @AdminRole('admin'|'reviewer') 声明，默认 reviewer（最低权限端点）。
 */
@Injectable()
export class AdminAuthGuard implements CanActivate {
  constructor(
    private readonly adminAuth: AdminAuthService,
    private readonly config: ConfigService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Request>();

    const ctx = await this.authenticate(req);
    const required =
      this.reflector.getAllAndOverride<AdminRoleName>(ADMIN_ROLE_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? 'reviewer';
    if (!roleSatisfies(ctx.role, required)) throw err.forbidden();

    (req as unknown as Record<string, unknown>).adminUser = ctx;
    return true;
  }

  private async authenticate(req: Request): Promise<AdminRequestContext> {
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme === 'Bearer' && token) {
      const admin: AdminUserEntity = await this.adminAuth.verifyAdminToken(token);
      return { id: admin.id, username: admin.username, role: admin.role };
    }

    // x-admin-token 兜底（过渡方案）：env 未配置时管理端整体关闭（404，不暴露端点存在性）
    const expected = this.config.get<string>('ADMIN_TOKEN');
    if (!expected) throw err.notFound();
    if (req.headers['x-admin-token'] !== expected) throw err.tokenInvalid();
    return { id: null, username: 'token', role: 'admin' };
  }
}
