import { Global, Module } from '@nestjs/common';
import { LlmModule } from '../llm/llm.module';
import { AdminAuthController } from './admin-auth.controller';
import { AdminAuthGuard } from './admin-auth.guard';
import { AdminAuthService } from './admin-auth.service';
import { AdminConfigController } from './admin-config.controller';
import { AdminConsoleController } from './admin-console.controller';
import { RuntimeConfigService } from './runtime-config.service';

/**
 * 内嵌管理控制台：管理员账号体系（登录 + 角色，admin-auth.*）+
 * 食物审核（端点见 food/admin-food.controller.ts）+
 * 打卡审核（端点见 social/admin-posts.controller.ts）+
 * 服务端 API 配置（LLM 运行时修改免重启）+ /admin 静态页。
 * @Global：RuntimeConfigService 需被 LlmModule 的 provider 工厂注入（免重启切换），
 * 而 LlmModule 不能反向 import AdminModule（会成环）；AdminAuthGuard 导出供
 * food/social 模块的管理控制器 @UseGuards 使用。
 */
@Global()
@Module({
  imports: [LlmModule],
  controllers: [AdminAuthController, AdminConfigController, AdminConsoleController],
  providers: [AdminAuthService, AdminAuthGuard, RuntimeConfigService],
  exports: [AdminAuthService, AdminAuthGuard, RuntimeConfigService],
})
export class AdminModule {}
