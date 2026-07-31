import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/** 按用户限流（JWT 全局守卫先于本守卫执行，req.user 必已注入） */
@Injectable()
export class UserThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, unknown>): Promise<string> {
    const user = req.user as { userId?: string } | undefined;
    return user?.userId ?? (req.ip as string);
  }
}
