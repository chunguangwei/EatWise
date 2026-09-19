import { CanActivate, ExecutionContext, Inject, Injectable } from '@nestjs/common';
import { Request } from 'express';
import { err } from '../common/errors/business.exception';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';

/**
 * 用户态管理员守卫（移动端审批中心）：与 AdminAuthGuard 不同，走用户 JWT 体系——
 * 全局 JwtAuthGuard 已验签并挂 req.user.userId，本守卫再按 User.role 门控：
 * 未认证/用户已删 → 401 AUTH_TOKEN_INVALID；role != admin → 403 FORBIDDEN
 * （移动端要给明确提示，不用 404 隐藏端点）。
 */
@Injectable()
export class UserAdminGuard implements CanActivate {
  constructor(@Inject(STORE_DRIVER) private readonly driver: StoreDriver) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Request>();
    const userId = (req as unknown as Record<string, { userId?: string }>).user?.userId;
    if (!userId) throw err.tokenInvalid(); // 防御：全局守卫未通过时不应到达这里
    const user = await this.driver.findUserById(userId);
    if (!user || user.deletedAt) throw err.tokenInvalid();
    if (user.role !== 'admin') throw err.forbidden();
    return true;
  }
}
