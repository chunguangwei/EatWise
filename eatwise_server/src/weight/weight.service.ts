import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { WeightLogEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId } from '../common/utils/id.util';
import { CreateWeightLogDto } from './weight.dto';

/** yyyy-MM-dd 合法性（含 13 月/40 日等正则漏网的真实日期校验） */
function isValidDateKey(date: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const parsed = new Date(`${date}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === date;
}

/**
 * 体重记录（阶段 C 体重管理闭环）：幂等 upsert（同 userId+date 覆写，
 * clientRequestId 重放返回首次结果，同键不同体 409）+ 区间查询 + 软删。
 * 鉴权走全局 JwtAuthGuard，口径与 WaterLog 一致。
 */
@Injectable()
export class WeightService {
  constructor(@Inject(STORE_DRIVER) private readonly driver: StoreDriver) {}

  /** POST /v1/weight-logs：幂等 upsert（同日覆写取最新） */
  async upsert(userId: string, dto: CreateWeightLogDto) {
    if (!isValidDateKey(dto.date)) throw err.validation({ date: 'invalid date' });
    const bodyFatPct = dto.bodyFatPct ?? null;
    const dup = await this.driver.findWeightLogByClientRequestId(userId, dto.clientRequestId);
    if (dup) {
      // 幂等重放：同键同体返回首次结果；同键不同体 = 客户端 bug
      const same =
        dup.date === dto.date && dup.weightKg === dto.weightKg && dup.bodyFatPct === bodyFatPct;
      if (!same) throw err.payloadMismatch();
      return this.view(dup);
    }
    const now = new Date();
    const existing = await this.driver.findWeightLogByUserAndDate(userId, dto.date);
    if (existing) {
      // 同日覆写：版本 +1，幂等键换绑为最新一次写入（重放按新键命中）
      const updated: WeightLogEntity = {
        ...existing,
        clientRequestId: dto.clientRequestId,
        weightKg: dto.weightKg,
        bodyFatPct,
        version: existing.version + 1,
        updatedAt: now,
      };
      await this.driver.saveWeightLog(updated);
      return this.view(updated);
    }
    const log: WeightLogEntity = {
      id: newId(),
      userId,
      clientRequestId: dto.clientRequestId,
      date: dto.date,
      weightKg: dto.weightKg,
      bodyFatPct,
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    await this.driver.saveWeightLog(log);
    return this.view(log);
  }

  /** GET /v1/weight-logs?from&to：区间查询（含端点，排除 tombstone，date 升序） */
  async list(userId: string, from: string | undefined, to: string | undefined) {
    const effectiveFrom = from ?? '1970-01-01';
    const effectiveTo = to ?? new Date().toISOString().slice(0, 10);
    if (!isValidDateKey(effectiveFrom)) throw err.validation({ from: 'invalid date' });
    if (!isValidDateKey(effectiveTo)) throw err.validation({ to: 'invalid date' });
    if (effectiveFrom > effectiveTo) throw err.validation({ from: 'from must be <= to' });
    const rows = await this.driver.findWeightLogsByUserRange(userId, effectiveFrom, effectiveTo);
    return { logs: rows.map((e) => this.view(e)) };
  }

  /** DELETE /v1/weight-logs/:id：软删 tombstone（重复删除幂等；他人记录 404） */
  async remove(userId: string, id: string) {
    const log = await this.driver.findWeightLogById(id);
    if (!log || log.userId !== userId) throw err.notFound();
    if (!log.deletedAt) {
      log.deletedAt = new Date();
      log.version += 1;
      log.updatedAt = new Date();
      await this.driver.saveWeightLog(log);
    }
    return this.view(log);
  }

  private view(e: WeightLogEntity) {
    return {
      id: e.id,
      clientRequestId: e.clientRequestId,
      date: e.date,
      weightKg: e.weightKg,
      bodyFatPct: e.bodyFatPct,
      version: e.version,
      createdAt: e.createdAt.toISOString(),
      updatedAt: e.updatedAt.toISOString(),
      ...(e.deletedAt ? { deletedAt: e.deletedAt.toISOString() } : {}),
    };
  }
}
