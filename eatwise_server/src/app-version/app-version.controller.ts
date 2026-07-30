import { Controller, Get, Query } from '@nestjs/common';
import { IsIn } from 'class-validator';
import { Public } from '../auth/public.decorator';
import { AppPlatform, AppVersionService } from './app-version.service';

class LatestVersionQuery {
  /** 目标平台（契约：android|ios）。 */
  @IsIn(['android', 'ios'])
  platform!: AppPlatform;
}

@Controller()
export class AppVersionController {
  constructor(private readonly appVersion: AppVersionService) {}

  /** 应用内更新检查：最新版本查询（公开接口，服务端代理 GitHub Releases）。 */
  @Public()
  @Get('app/version/latest')
  getLatest(@Query() query: LatestVersionQuery) {
    return this.appVersion.getLatest(query.platform);
  }
}
