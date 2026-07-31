import { Global, Module } from '@nestjs/common';
import { LlmModule } from '../llm/llm.module';
import { AdminConfigController } from './admin-config.controller';
import { AdminConsoleController } from './admin-console.controller';
import { RuntimeConfigService } from './runtime-config.service';

/**
 * 内嵌管理控制台：食物审核（端点见 food/admin-food.controller.ts）+
 * 打卡审核（端点见 social/admin-posts.controller.ts）+
 * 服务端 API 配置（LLM 运行时修改免重启）+ /admin 静态页。
 * @Global：RuntimeConfigService 需被 LlmModule 的 provider 工厂注入（免重启切换），
 * 而 LlmModule 不能反向 import AdminModule（会成环）。
 */
@Global()
@Module({
  imports: [LlmModule],
  controllers: [AdminConfigController, AdminConsoleController],
  providers: [RuntimeConfigService],
  exports: [RuntimeConfigService],
})
export class AdminModule {}
