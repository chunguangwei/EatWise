import { Body, Controller, Delete, Get, Patch, Post } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { PatchUserDto } from './user.dto';
import { UserService } from './user.service';

@Controller('users')
export class UserController {
  constructor(private readonly users: UserService) {}

  /** U1 读取当前用户（含营养目标计算结果快照；手机号脱敏返回） */
  @Get('me')
  getMe(@CurrentUser() user: AuthUser) {
    return this.users.getMe(user.userId);
  }

  /** U2 修改资料（字段级 LWW + 目标重算；DTO 校验时区/数值范围） */
  @Patch('me')
  patchMe(@CurrentUser() user: AuthUser, @Body() dto: PatchUserDto) {
    return this.users.patchMe(user.userId, dto);
  }

  /** U3 申请数据导出（合规 §4.2）：聚合全量个人数据，JSON 直接返回（只读，天然幂等） */
  @Post('me/export')
  exportMe(@CurrentUser() user: AuthUser) {
    return this.users.exportMe(user.userId);
  }

  /** U5 申请删除账号（合规 §4.3）：7 天冷静期〔假设〕，幂等 */
  @Post('me/deletion')
  requestDeletion(@CurrentUser() user: AuthUser) {
    return this.users.requestDeletion(user.userId);
  }

  /** U6 冷静期内撤销删除申请（幂等；冷静期内重新登录亦视为撤销，见 AuthService） */
  @Delete('me/deletion')
  cancelDeletion(@CurrentUser() user: AuthUser) {
    return this.users.cancelDeletion(user.userId);
  }
}
