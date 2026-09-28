import { Controller, Get, Res } from '@nestjs/common';
import { Response } from 'express';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';

/**
 * 法务静态页（App Store Connect 要求：隐私政策/用户协议必须有公网可访问 URL）。
 * 路由 /privacy、/terms（在 main.ts 中从全局 /v1 前缀排除），匿名可访问。
 * 页面源文件 public/*.html，由 scripts/build_legal_pages.mjs 从
 * docs/compliance/*.md 生成（文本三处同步：i18n legal.* / docs / public HTML）。
 * 与 admin console 同模式：nest-cli assets 拷贝到 dist/public（Docker runtime
 * 阶段只留 dist，必须走 assets 才能进生产镜像）。
 */
@Public()
@Controller()
export class LegalPagesController {
  @Get('privacy')
  privacy(@Res() res: Response) {
    this.send(res, 'privacy.html');
  }

  @Get('terms')
  terms(@Res() res: Response) {
    this.send(res, 'terms.html');
  }

  private send(res: Response, name: string) {
    // prod（dist/legal → dist/public，nest assets 拷贝）与 dev 直跑源码两种布局
    const candidates = [join(__dirname, '..', 'public', name), join(process.cwd(), 'public', name)];
    const file = candidates.find((p) => existsSync(p));
    if (!file) throw err.notFound();
    // 纯静态页无内联脚本，helmet 默认 CSP（style-src 含 'unsafe-inline'）够用，不放宽
    res.type('html').send(readFileSync(file, 'utf8'));
  }
}
