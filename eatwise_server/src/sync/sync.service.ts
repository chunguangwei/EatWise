import { Inject, Injectable } from '@nestjs/common';
import { BusinessException, err } from '../common/errors/business.exception';
import { FoodEntryEntity, NutritionSnapshot, WaterLogEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { clampPageLimit } from '../common/utils/pagination.util';
import { NutritionService, round1 } from '../nutrition/nutrition.service';
import { localDateOf } from '../common/utils/time.util';
import { CreateEntryDto, SyncOpDto } from './sync.dto';

const SYNC_TOKEN_TTL_MS = 30 * 24 * 3600 * 1000; // syncToken 有效期 30 天〔假设〕

export interface OpResult {
  clientRequestId: string;
  status: 'applied' | 'conflict' | 'error';
  conflictType?: 'version_mismatch' | 'deleted_vs_modified';
  serverEntry?: unknown;
  error?: { code: string };
}

@Injectable()
export class SyncService {
  constructor(
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
    private readonly nutrition: NutritionService,
  ) {}

  // ===== E1 单条创建（幂等，D-20）=====
  async createEntry(userId: string, dto: CreateEntryDto) {
    const endpoint = 'food-entries/create';
    const hash = payloadHash(dto);
    const existing = await this.driver.findFoodEntryByClientRequestId(userId, dto.clientRequestId);
    if (existing) {
      const hit = await this.driver.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
      if (hit && hit.payloadHash !== hash) throw err.payloadMismatch(); // 同键不同体 = 客户端 bug
      return hit?.responseBody;
    }
    const entry = await this.buildEntry(userId, dto.clientRequestId, dto);
    const response = {
      entry: this.entryView(entry),
      dailyNutrition: await this.dailyNutritionOf(entry),
    };
    await this.driver.saveIdempotencyRecord({
      userId,
      clientRequestId: dto.clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: new Date(),
    });
    return response;
  }

  // ===== E4 / sync/push 批量上行（逐条幂等、逐条 LWW 冲突返回，整体永不整体失败）=====
  async push(userId: string, ops: SyncOpDto[]) {
    // 批内顺序处理（保持历史语义：同批同 clientRequestId 的后续 op 能看到前序写入）
    const results: OpResult[] = [];
    for (const op of ops) results.push(await this.applyOp(userId, op));
    return { results, syncToken: this.encodeToken(new Date(), newId()) };
  }

  private async applyOp(userId: string, op: SyncOpDto): Promise<OpResult> {
    try {
      if (op.entity === 'waterLog') return await this.applyWaterOp(userId, op);
      if (op.entity !== 'foodEntry') {
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          error: { code: 'VALIDATION_ERROR' },
        };
      }
      switch (op.op) {
        case 'create':
          return await this.applyCreate(userId, op);
        case 'update':
          return await this.applyUpdate(userId, op);
        case 'delete':
          return await this.applyDelete(userId, op);
        default:
          return {
            clientRequestId: op.clientRequestId,
            status: 'error',
            error: { code: 'VALIDATION_ERROR' },
          };
      }
    } catch (e) {
      // 业务校验错误（如未知 foodId 的 VALIDATION_ERROR）保留原 code，不吞成 INTERNAL_ERROR
      const code = e instanceof BusinessException ? e.code : 'INTERNAL_ERROR';
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        error: { code },
      };
    }
  }

  private async applyCreate(userId: string, op: SyncOpDto): Promise<OpResult> {
    if (!op.payload?.foodId || op.payload.grams == null || !op.payload.eatenAt) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        error: { code: 'VALIDATION_ERROR' },
      };
    }
    const dup = await this.driver.findFoodEntryByClientRequestId(userId, op.clientRequestId);
    if (dup) {
      // 幂等重放：返回首次结果；同键不同体报 mismatch
      const same =
        dup.foodId === op.payload.foodId &&
        dup.grams === op.payload.grams &&
        dup.eatenAt.toISOString() === new Date(op.payload.eatenAt).toISOString();
      if (!same) {
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          error: { code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' },
        };
      }
      return {
        clientRequestId: op.clientRequestId,
        status: 'applied',
        serverEntry: this.entryView(dup),
      };
    }
    const entry = await this.buildEntry(userId, op.clientRequestId, {
      clientRequestId: op.clientRequestId,
      eatenAt: op.payload.eatenAt,
      foodId: op.payload.foodId,
      grams: op.payload.grams,
      inputMethod: op.payload.inputMethod ?? 'manual',
      photoUrl: op.payload.photoUrl,
    });
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: this.entryView(entry),
    };
  }

  private async applyUpdate(userId: string, op: SyncOpDto): Promise<OpResult> {
    const id = op.serverId ?? op.payload?.id;
    const entry = id ? await this.driver.findFoodEntryById(id) : null;
    if (!entry || entry.userId !== userId) {
      return { clientRequestId: op.clientRequestId, status: 'error', error: { code: 'NOT_FOUND' } };
    }
    if (entry.deletedAt) {
      // 删除 vs 修改不可合并：双份保留待用户处理（D-20）
      return {
        clientRequestId: op.clientRequestId,
        status: 'conflict',
        conflictType: 'deleted_vs_modified',
        serverEntry: {
          id: entry.id,
          deletedAt: entry.deletedAt.toISOString(),
          version: entry.version,
        },
      };
    }
    // LWW 版本检测：baseVersion 不符 → 返回服务端现值由客户端字段级合并后重试
    if (op.baseVersion == null || op.baseVersion !== entry.version) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'conflict',
        conflictType: 'version_mismatch',
        serverEntry: this.entryView(entry),
      };
    }
    const p = op.payload ?? {};
    if (p.eatenAt) entry.eatenAt = new Date(p.eatenAt);
    if (p.foodId) entry.foodId = p.foodId;
    if (p.grams != null) entry.grams = p.grams;
    if (p.inputMethod) entry.inputMethod = p.inputMethod;
    if (p.foodId || p.grams != null)
      entry.nutritionSnapshot = await this.snapshotOf(userId, entry.foodId, entry.grams);
    entry.version += 1;
    entry.updatedAt = new Date(); // LWW 仲裁基准 = 服务端时钟（客户端时间戳不采信，防腐层）
    await this.driver.saveFoodEntry(entry);
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: this.entryView(entry),
    };
  }

  private async applyDelete(userId: string, op: SyncOpDto): Promise<OpResult> {
    const id = op.serverId ?? op.payload?.id;
    const entry = id ? await this.driver.findFoodEntryById(id) : null;
    if (!entry || entry.userId !== userId) {
      return { clientRequestId: op.clientRequestId, status: 'error', error: { code: 'NOT_FOUND' } };
    }
    if (!entry.deletedAt) {
      if (op.baseVersion != null && op.baseVersion !== entry.version) {
        return {
          clientRequestId: op.clientRequestId,
          status: 'conflict',
          conflictType: 'version_mismatch',
          serverEntry: this.entryView(entry),
        };
      }
      entry.deletedAt = new Date();
      entry.version += 1;
      entry.updatedAt = new Date();
      await this.driver.saveFoodEntry(entry);
    }
    // 软删幂等：重复删除返回 applied
    return { clientRequestId: op.clientRequestId, status: 'applied' };
  }

  // ===== waterLog 轻量同步（两态：仅 create/delete，无 update——
  // 饮水无编辑/冲突场景〔假设〕；幂等 clientRequestId 同 foodEntry 口径）=====

  private async applyWaterOp(userId: string, op: SyncOpDto): Promise<OpResult> {
    switch (op.op) {
      case 'create':
        return await this.applyWaterCreate(userId, op);
      case 'delete':
        return await this.applyWaterDelete(userId, op);
      default:
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          error: { code: 'VALIDATION_ERROR' },
        };
    }
  }

  private async applyWaterCreate(userId: string, op: SyncOpDto): Promise<OpResult> {
    const amountMl = op.payload?.amountMl;
    const loggedAt = op.payload?.loggedAt;
    if (amountMl == null || amountMl <= 0 || !loggedAt) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        error: { code: 'VALIDATION_ERROR' },
      };
    }
    const dup = await this.findWaterByClientRequestId(userId, op.clientRequestId);
    if (dup) {
      // 幂等重放：同键同体返回首次结果；同键不同体 = 客户端 bug
      const same =
        dup.amountMl === amountMl &&
        dup.loggedAt.toISOString() === new Date(loggedAt).toISOString();
      if (!same) {
        return {
          clientRequestId: op.clientRequestId,
          status: 'error',
          error: { code: 'IDEMPOTENCY_PAYLOAD_MISMATCH' },
        };
      }
      return {
        clientRequestId: op.clientRequestId,
        status: 'applied',
        serverEntry: this.waterLogView(dup),
      };
    }
    const now = new Date();
    const log: WaterLogEntity = {
      id: newId(),
      userId,
      clientRequestId: op.clientRequestId,
      amountMl,
      loggedAt: new Date(loggedAt),
      localDate: op.payload?.localDate ?? '',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    await this.driver.createWaterLog(log);
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: this.waterLogView(log),
    };
  }

  private async applyWaterDelete(userId: string, op: SyncOpDto): Promise<OpResult> {
    const id = op.serverId ?? op.payload?.id;
    // 驱动无按 waterLog id 单查方法：本用户增量扫描（含 tombstone）覆盖 id 与幂等键两种定位
    const logs = await this.driver.findWaterLogsSince(userId, new Date(0));
    const log =
      (id ? logs.find((e) => e.id === id) : undefined) ??
      // 兜底：create 已上行但客户端未拿到 serverId（响应丢失）→ 按行幂等键定位
      (op.payload?.clientRequestId
        ? logs.find((e) => e.clientRequestId === op.payload?.clientRequestId)
        : undefined);
    if (!log || log.userId !== userId) {
      return { clientRequestId: op.clientRequestId, status: 'error', error: { code: 'NOT_FOUND' } };
    }
    if (!log.deletedAt) await this.driver.deleteWaterLog(userId, log.clientRequestId);
    // 软删幂等：重复删除返回 applied
    return { clientRequestId: op.clientRequestId, status: 'applied' };
  }

  /** 幂等键定位（含 tombstone）：驱动按 userId 增量扫描，since=epoch 即全量 */
  private async findWaterByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): Promise<WaterLogEntity | null> {
    const logs = await this.driver.findWaterLogsSince(userId, new Date(0));
    return logs.find((e) => e.clientRequestId === clientRequestId) ?? null;
  }

  private waterLogView(e: WaterLogEntity) {
    return {
      entity: 'waterLog',
      id: e.id,
      clientRequestId: e.clientRequestId,
      amountMl: e.amountMl,
      loggedAt: e.loggedAt.toISOString(),
      localDate: e.localDate,
      version: e.version,
      updatedAt: e.updatedAt.toISOString(),
    };
  }
  // ===== E6 / sync/pull 增量下行（syncToken 游标）=====
  async pull(userId: string, syncToken: string | undefined, limit = 200) {
    limit = clampPageLimit(limit, 200, 1000); // 非法 limit（负数/NaN）回落默认，防游标死循环
    let after: { ts: number; id: string } | null = null;
    if (syncToken) after = this.decodeToken(syncToken);

    // 驱动已按 (updatedAt asc, id asc) 排序 —— 与 syncToken 游标语义同口径（含 tombstone）
    const rows = await this.driver.listFoodEntriesByUser(userId);
    const all = rows.filter(
      (e) =>
        !after ||
        e.updatedAt.getTime() > after.ts ||
        (e.updatedAt.getTime() === after.ts && e.id > after.id),
    );

    // 饮水记录随行下行（轻量两态，不分页〔假设：单用户饮水量小〕；
    // 复用同一 syncToken 游标语义：updatedAt 晚于游标的全部返回）
    const waterLogs = await this.driver.findWaterLogsSince(userId, new Date(after?.ts ?? 0));
    const waterChanges = waterLogs.map((e) =>
      e.deletedAt
        ? { tombstone: { entity: 'waterLog', id: e.id, deletedAt: e.deletedAt.toISOString() } }
        : this.waterLogView(e),
    );

    const page = all.slice(0, limit);
    const last = page[page.length - 1];
    return {
      changes: page.map((e) =>
        e.deletedAt
          ? { tombstone: { id: e.id, deletedAt: e.deletedAt.toISOString() } }
          : this.entryView(e),
      ),
      waterLogChanges: waterChanges,
      syncToken: last
        ? this.encodeToken(last.updatedAt, last.id)
        : (syncToken ?? this.encodeToken(new Date(), '')),
      hasMore: all.length > page.length,
    };
  }

  private encodeToken(at: Date, id: string): string {
    return `st_${Buffer.from(JSON.stringify({ ts: at.getTime(), id })).toString('base64url')}`;
  }

  private decodeToken(token: string): { ts: number; id: string } {
    try {
      if (!token.startsWith('st_')) throw new Error('bad prefix');
      const parsed = JSON.parse(Buffer.from(token.slice(3), 'base64url').toString('utf8'));
      if (typeof parsed.ts !== 'number') throw new Error('bad ts');
      if (Date.now() - parsed.ts > SYNC_TOKEN_TTL_MS) throw new Error('expired');
      return { ts: parsed.ts, id: String(parsed.id ?? '') };
    } catch {
      throw err.invalidSyncToken(); // 客户端需全量重拉
    }
  }

  // ===== 内部工具 =====

  private async buildEntry(
    userId: string,
    clientRequestId: string,
    dto: CreateEntryDto,
  ): Promise<FoodEntryEntity> {
    const now = new Date();
    const entry: FoodEntryEntity = {
      id: newId(),
      userId,
      clientRequestId,
      eatenAt: new Date(dto.eatenAt),
      foodId: dto.foodId,
      grams: dto.grams,
      inputMethod: dto.inputMethod,
      photoUrl: dto.photoUrl ?? null,
      nutritionSnapshot: await this.snapshotOf(userId, dto.foodId, dto.grams),
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    await this.driver.saveFoodEntry(entry);
    return entry;
  }

  /**
   * 营养快照：服务端按食物库每 100g 值 × grams/100 换算（快照防食物库更新回溯改历史）。
   * 共享库未命中时回落本人自定义食物（乐观入账口径：未入库食品先记先同步，
   * 审核驳回再由 reject 路径级联清除）——此前只查共享库，自定义食物的记录
   * 上行必 4xx，客户端 T7 回滚静默删除（「不报错就没了」根因）。
   */
  private async snapshotOf(
    userId: string,
    foodId: string,
    grams: number,
  ): Promise<NutritionSnapshot> {
    const food =
      (await this.driver.findFoodById(foodId)) ?? (await this.driver.findCustomFoodById(foodId));
    if (!food || ('userId' in food && food.userId !== userId)) {
      throw err.validation({ foodId: 'unknown food' });
    }
    const f = grams / 100;
    return {
      kcal: round1(food.kcalPer100g * f),
      proteinG: round1(food.proteinPer100g * f),
      carbsG: round1(food.carbsPer100g * f),
      fatG: round1(food.fatPer100g * f),
    };
  }

  private async dailyNutritionOf(entry: FoodEntryEntity) {
    const user = await this.driver.findUserById(entry.userId);
    const tz = user?.timezone ?? 'Asia/Shanghai';
    const date = localDateOf(entry.eatenAt, tz);
    const totals = await this.nutrition.aggregate(entry.userId, date, tz);
    return {
      date,
      kcal: totals.kcal,
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
    };
  }

  entryView(e: FoodEntryEntity) {
    return {
      id: e.id,
      clientRequestId: e.clientRequestId,
      eatenAt: e.eatenAt.toISOString(),
      foodId: e.foodId,
      grams: e.grams,
      inputMethod: e.inputMethod,
      nutritionSnapshot: e.nutritionSnapshot,
      version: e.version,
      updatedAt: e.updatedAt.toISOString(),
    };
  }
}
