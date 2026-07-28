import { Body, Controller, Get, Patch } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { UserService } from './user.service';

@Controller('users')
export class UserController {
  constructor(private readonly users: UserService) {}

  /** U1 读取当前用户（含营养目标计算结果快照） */
  @Get('me')
  getMe(@CurrentUser() user: AuthUser) {
    return this.users.getMe(user.userId);
  }

  /** U2 修改资料（字段级 LWW + 目标重算） */
  @Patch('me')
  patchMe(@CurrentUser() user: AuthUser, @Body() body: Record<string, unknown>) {
    return this.users.patchMe(user.userId, body);
  }
}
