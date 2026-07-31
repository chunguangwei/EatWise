import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AdminRequestContext } from './admin-auth.guard';

/** 取当前管理员上下文（经 AdminAuthGuard 认证后挂在 req.adminUser） */
export const CurrentAdmin = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AdminRequestContext => {
    const req = ctx.switchToHttp().getRequest<Record<string, unknown>>();
    return req.adminUser as AdminRequestContext;
  },
);
