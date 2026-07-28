import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { err } from '../common/errors/business.exception';
import { IS_PUBLIC_KEY } from './public.decorator';

/** 全局 JWT 守卫：Authorization: Bearer <accessToken>（契约 §1.2） */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const req = context.switchToHttp().getRequest<Request>();
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) throw err.tokenInvalid();

    try {
      const payload = await this.jwt.verifyAsync<{ sub: string }>(token);
      (req as unknown as Record<string, unknown>).user = { userId: payload.sub };
      return true;
    } catch (e) {
      if ((e as Error).name === 'TokenExpiredError') throw err.tokenExpired();
      throw err.tokenInvalid();
    }
  }
}
