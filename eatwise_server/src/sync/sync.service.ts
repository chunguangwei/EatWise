import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore, FoodEntryEntity, NutritionSnapshot } from '../common/store/data-store';
import { newId, payloadHash } from '../common/utils/id.util';
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
    private readonly store: DataStore,
    private readonly nutrition: NutritionService,
  ) {}

  // ===== E1 单条创建（幂等，D-20）=====
  createEntry(userId: string, dto: CreateEntryDto) {
    const endpoint = 'food-entries/create';
    const hash = payloadHash(dto);
    const existing = this.findByClientRequestId(userId, dto.clientRequestId);
    if (existing) {
      const hit = this.store.idempotency.get(
        this.store.idemKey(userId, endpoint, dto.clientRequestId),
      );
      if (hit && hit.payloadHash !== hash) throw err.payloadMismatch(); // 同键不同体 = 客户端 bug
      return hit?.responseBody;
    }
    const entry = this.buildEntry(userId, dto.clientRequestId, dto);
    const response = {
      entry: this.entryView(entry),
      dailyNutrition: this.dailyNutritionOf(entry),
    };
    this.store.idempotency.set(this.store.idemKey(userId, endpoint, dto.clientRequestId), {
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
  push(userId: string, ops: SyncOpDto[]) {
    const results = ops.map((op) => this.applyOp(userId, op));
    return { results, syncToken: this.encodeToken(new Date(), newId()) };
  }

  private applyOp(userId: string, op: SyncOpDto): OpResult {
    try {
      switch (op.op) {
        case 'create':
          return this.applyCreate(userId, op);
        case 'update':
          return this.applyUpdate(userId, op);
        case 'delete':
          return this.applyDelete(userId, op);
        default:
          return {
            clientRequestId: op.clientRequestId,
            status: 'error',
            error: { code: 'VALIDATION_ERROR' },
          };
      }
    } catch {
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        error: { code: 'INTERNAL_ERROR' },
      };
    }
  }

  private applyCreate(userId: string, op: SyncOpDto): OpResult {
    if (!op.payload?.foodId || op.payload.grams == null || !op.payload.eatenAt) {
      return {
        clientRequestId: op.clientRequestId,
        status: 'error',
        error: { code: 'VALIDATION_ERROR' },
      };
    }
    const dup = this.findByClientRequestId(userId, op.clientRequestId);
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
    const entry = this.buildEntry(userId, op.clientRequestId, {
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

  private applyUpdate(userId: string, op: SyncOpDto): OpResult {
    const id = op.serverId ?? op.payload?.id;
    const entry = id ? this.store.foodEntries.get(id) : undefined;
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
      entry.nutritionSnapshot = this.snapshotOf(entry.foodId, entry.grams);
    entry.version += 1;
    entry.updatedAt = new Date(); // LWW 仲裁基准 = 服务端时钟（客户端时间戳不采信，防腐层）
    return {
      clientRequestId: op.clientRequestId,
      status: 'applied',
      serverEntry: this.entryView(entry),
    };
  }

  private applyDelete(userId: string, op: SyncOpDto): OpResult {
    const id = op.serverId ?? op.payload?.id;
    const entry = id ? this.store.foodEntries.get(id) : undefined;
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
    }
    // 软删幂等：重复删除返回 applied
    return { clientRequestId: op.clientRequestId, status: 'applied' };
  }

  // ===== E6 / sync/pull 增量下行（syncToken 游标）=====
  pull(userId: string, syncToken: string | undefined, limit = 200) {
    let after: { ts: number; id: string } | null = null;
    if (syncToken) after = this.decodeToken(syncToken);

    const all = [...this.store.foodEntries.values()]
      .filter((e) => e.userId === userId)
      .filter(
        (e) =>
          !after ||
          e.updatedAt.getTime() > after.ts ||
          (e.updatedAt.getTime() === after.ts && e.id > after.id),
      )
      .sort((a, b) => a.updatedAt.getTime() - b.updatedAt.getTime() || a.id.localeCompare(b.id));

    const page = all.slice(0, limit);
    const last = page[page.length - 1];
    return {
      changes: page.map((e) =>
        e.deletedAt
          ? { tombstone: { id: e.id, deletedAt: e.deletedAt.toISOString() } }
          : this.entryView(e),
      ),
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

  private findByClientRequestId(
    userId: string,
    clientRequestId: string,
  ): FoodEntryEntity | undefined {
    return [...this.store.foodEntries.values()].find(
      (e) => e.userId === userId && e.clientRequestId === clientRequestId,
    );
  }

  private buildEntry(
    userId: string,
    clientRequestId: string,
    dto: CreateEntryDto,
  ): FoodEntryEntity {
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
      nutritionSnapshot: this.snapshotOf(dto.foodId, dto.grams),
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    this.store.foodEntries.set(entry.id, entry);
    return entry;
  }

  /** 营养快照：服务端按食物库每 100g 值 × grams/100 换算（快照防食物库更新回溯改历史） */
  private snapshotOf(foodId: string, grams: number): NutritionSnapshot {
    const food = this.store.foods.get(foodId);
    if (!food) throw err.validation({ foodId: 'unknown food' });
    const f = grams / 100;
    return {
      kcal: round1(food.kcalPer100g * f),
      proteinG: round1(food.proteinPer100g * f),
      carbsG: round1(food.carbsPer100g * f),
      fatG: round1(food.fatPer100g * f),
    };
  }

  private dailyNutritionOf(entry: FoodEntryEntity) {
    const tz = this.store.users.get(entry.userId)?.timezone ?? 'Asia/Shanghai';
    const date = localDateOf(entry.eatenAt, tz);
    const totals = this.nutrition.aggregate(entry.userId, date, tz);
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
