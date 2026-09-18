import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';
import { AdminAuthGuard } from './admin-auth.guard';
import { AdminRole } from './admin-role.decorator';
import { AdminUsersService } from './admin-users.service';

/**
 * 管理端：注册用户查看（只读列表）。
 * 鉴权与 /v1/admin/posts、/v1/admin/food-candidates 一致：AdminAuthGuard
 * （管理员 JWT 或 x-admin-token 兜底）+ @AdminRole('reviewer') —— reviewer / admin 均可查看。
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
}
