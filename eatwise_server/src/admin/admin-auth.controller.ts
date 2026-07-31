import { Body, Controller, Get, HttpCode, Post, UseGuards } from '@nestjs/common';
import { IsString, MinLength } from 'class-validator';
import { Public } from '../auth/public.decorator';
import { AdminAuthGuard, AdminRequestContext } from './admin-auth.guard';
import { AdminAuthService } from './admin-auth.service';
import { AdminRole } from './admin-role.decorator';
import { CurrentAdmin } from './current-admin.decorator';

export class AdminLoginDto {
  @IsString()
  @MinLength(1)
  username!: string;

  @IsString()
  @MinLength(1)
  password!: string;
}

/**
 * 管理员认证（与用户体系完全独立）：
 * - POST /v1/admin/auth/login：账号密码登录（限流 5 次/分钟/用户名〔假设〕）→ 管理员 JWT（12h）
 * - GET /v1/admin/auth/me：当前管理员信息（JWT 或 x-admin-token 兜底均可）
 */
@Public()
@Controller('admin/auth')
export class AdminAuthController {
  constructor(private readonly adminAuth: AdminAuthService) {}

  @Post('login')
  @HttpCode(200)
  login(@Body() dto: AdminLoginDto) {
    return this.adminAuth.login(dto.username, dto.password);
  }

  @Get('me')
  @UseGuards(AdminAuthGuard)
  @AdminRole('reviewer') // 任意已认证管理员（admin / reviewer / token 兜底）
  me(@CurrentAdmin() admin: AdminRequestContext) {
    return { id: admin.id, username: admin.username, role: admin.role };
  }
}
