import { Controller, Get, Res } from '@nestjs/common';
import { Response } from 'express';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { Public } from '../auth/public.decorator';
import { err } from '../common/errors/business.exception';

/**
 * 管理控制台静态页（单文件 index.html，原生 JS 无构建依赖）。
 * 路由为 /admin（在 main.ts 中从全局 /v1 前缀排除）；页面本身不鉴权，
 * 所有数据仍走 /v1/admin/*（x-admin-token 由页面内输入并随请求携带）。
 */
@Public()
@Controller('admin')
export class AdminConsoleController {
  @Get()
  page(@Res() res: Response) {
    // dev（ts-jest/nest start 源码路径）与 prod（nest build 拷贝 assets 到 dist）两种布局
    const candidates = [
      join(__dirname, 'console', 'index.html'),
      join(process.cwd(), 'src', 'admin', 'console', 'index.html'),
    ];
    const file = candidates.find((p) => existsSync(p));
    if (!file) throw err.notFound();
    // 页面为内联 JS/CSS 单文件：helmet 默认 CSP（script-src 'self'）会拦内联脚本，
    // 仅对本响应放宽（API 响应不受影响）
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
    );
    res.type('html').send(readFileSync(file, 'utf8'));
  }
}
