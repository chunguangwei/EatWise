import { Controller, Get } from '@nestjs/common';
import { Public } from '../auth/public.decorator';

@Controller()
export class HealthController {
  /** 健康检查（公开接口，契约 §1.2） */
  @Public()
  @Get('health')
  health() {
    return { status: 'ok' };
  }
}
