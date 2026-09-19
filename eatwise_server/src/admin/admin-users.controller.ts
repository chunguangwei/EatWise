import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { Body, HttpCode, Param, Patch } from '@nestjs/common';
import { IsIn } from 'class-validator';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { UserRoleName } from '../common/store/data-store';
import { AdminAuthGuard } from './admin-auth.guard';
import { AdminRole } from './admin-role.decorator';
import { AdminUsersService } from './admin-users.service';

/** 设置用户角色（仅管理端 admin；user=一般用户 / admin=管理员，移动端审批中心可见） */
export class UpdateUserRoleDto {
  @IsIn(['user', 'admin'])
  role: UserRoleName;
}

/**
 * 管理端：注册用户查看（只读列表）+ 角色设置。
 * 鉴权与 /v1/admin/posts、/v1/admin/food-candidates 一致：AdminAuthGuard
 * （管理员 JWT 或 x-admin-token 兜底）；列表 reviewer 可看，角色设置仅 admin。
 */
@Public()
@UseGuards(AdminAuthGuard)
@AdminRole('reviewer')
@Controller('admin/users')
export class AdminUsersController {
  constructor(private readonly users: AdminUsersService) {}

  /** 用户列表：?keyword=（模糊匹配 username/phone/nickname）+ page/pageSize（≤100）页码分页 */
  @Get()
  list(
    @Query('keyword') keyword?: string,
    @Query('page') page?: string,
    @Query('pageSize') pageSize?: string,
  ) {
    const p = page === undefined ? 1 : Number(page);
    const size = pageSize === undefined ? 20 : Number(pageSize);
    if (!Number.isInteger(p) || p < 1) throw err.validation({ page: 'must be integer >= 1' });
    if (!Number.isInteger(size) || size < 1) {
      throw err.validation({ pageSize: 'must be integer >= 1' });
    }
    return this.users.listUsers(keyword, p, size);
  }

  /** 设置用户角色（仅 admin）：body {role: 'user'|'admin'}，幂等（重复设置同值返回当前态） */
  @Patch(':id/role')
  @AdminRole('admin')
  @HttpCode(200)
  setRole(@Param('id') userId: string, @Body() dto: UpdateUserRoleDto) {
    return this.users.setUserRole(userId, dto.role);
  }
}
