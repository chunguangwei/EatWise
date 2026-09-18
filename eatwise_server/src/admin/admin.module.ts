import { Global, Module } from '@nestjs/common';
import { AdminAuthController } from './admin-auth.controller';
import { AdminAuthGuard } from './admin-auth.guard';
import { AdminAuthService } from './admin-auth.service';
import { AdminConsoleController } from './admin-console.controller';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';

/**
 * 内嵌管理控制台：管理员账号体系（登录 + 角色，admin-auth.*）+
 * 注册用户查看（admin-users.*）+
 * 食物审核（端点见 food/admin-food.controller.ts）+
 * 打卡审核（端点见 social/admin-posts.controller.ts）+ /admin 静态页。
 * @Global：AdminAuthGuard 导出供 food/social 模块的管理控制器 @UseGuards 使用。
 */
@Global()
@Module({
  controllers: [AdminAuthController, AdminConsoleController, AdminUsersController],
  providers: [AdminAuthService, AdminAuthGuard, AdminUsersService],
  exports: [AdminAuthService, AdminAuthGuard],
})
export class AdminModule {}
