import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UserService } from './user.service';

/**
 * 到期删除扫描（合规 §4.3：冷静期结束后 ≤24h 完成物理删除/匿名化）。
 * 简单 interval 扫描（默认 60s，DELETION_SCAN_INTERVAL_MS 可调）；
 * 〔假设〕MVP 单机部署够用，多实例部署时应换分布式锁/队列防重复执行。
 */
@Injectable()
export class DeletionScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('DeletionScheduler');
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly users: UserService,
    private readonly config: ConfigService,
  ) {}

  onModuleInit() {
    const intervalMs = Number(this.config.get('DELETION_SCAN_INTERVAL_MS', 60_000));
    this.timer = setInterval(() => {
      this.users.executeDueDeletions().catch((e: Error) => {
        this.logger.warn(`到期删除扫描失败: ${e.message}`);
      });
    }, intervalMs);
    this.timer.unref(); // 不阻塞进程退出（测试/优雅停机）
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
}
