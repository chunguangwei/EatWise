import { Inject, Injectable, Optional } from '@nestjs/common';
import { err } from '../../common/errors/business.exception';
import { isPer100gInRange } from '../food.rules';

/** 条码查询结果视图（与 K1 搜索命中同构，客户端复用同一映射落本地缓存） */
export interface BarcodeFoodView {
  id: string;
  barcode: string;
  nameZh: string;
  nameEn: string;
  aliases: string[];
  kcalPer100g: number;
  proteinPer100g: number;
  carbsPer100g: number;
  fatPer100g: number;
  /** eatwise = 自有共享库命中（条码众包上架）；openfoodfacts = OFF 代理命中 */
  source: 'eatwise' | 'openfoodfacts';
  isCustom: false;
}

export interface BarcodeServiceOptions {
  /** 单次 OFF 请求超时（默认 8s） */
  timeoutMs?: number;
  /** 结果缓存 TTL（默认 30 天〔假设〕） */
  cacheTtlMs?: number;
  /** 可注入 mock（测试用），默认全局 fetch */
  fetchFn?: typeof fetch;
}

/** EAN-8/13、UPC-A 等：8–14 位纯数字 */
export const BARCODE_PATTERN = /^\d{8,14}$/;

const OFF_BASE_URL = 'https://world.openfoodfacts.org/api/v2/product';
/** OFF 使用条款要求带可识别 User-Agent（含联系方式占位〔假设〕） */
const USER_AGENT = 'EatWise/1.0 (barcode lookup; https://github.com/eatwise)';
const KJ_PER_KCAL = 4.184;

interface CacheEntry {
  view: BarcodeFoodView;
  expiresAt: number;
}

/**
 * 包装食品条码查询（食物库扩充第一层方案）：代理 Open Food Facts v2。
 *
 * 降级策略：OFF 无该商品 / 超时 / 网络错误 / 数据缺字段或越界，一律
 * 404 FOOD_BARCODE_NOT_FOUND（客户端据此走「手动搜索 / 自定义食物」承接）。
 * 命中结果按条码缓存（内存 Map，TTL 30 天〔假设〕；未命中不缓存——
 * OFF 商品库持续增长，负缓存会挡住后来收录的商品〔假设〕）。
 */
@Injectable()
export class BarcodeService {
  private readonly timeoutMs: number;
  private readonly cacheTtlMs: number;
  private readonly fetchFn: typeof fetch;
  private readonly cache = new Map<string, CacheEntry>();

  constructor(@Optional() @Inject('BARCODE_OPTIONS') opts?: BarcodeServiceOptions) {
    this.timeoutMs = opts?.timeoutMs ?? 8_000;
    this.cacheTtlMs = opts?.cacheTtlMs ?? 30 * 24 * 3600 * 1000;
    this.fetchFn = opts?.fetchFn ?? fetch;
  }

  async lookup(rawCode: string): Promise<BarcodeFoodView> {
    const code = rawCode.trim();
    if (!BARCODE_PATTERN.test(code)) {
      throw err.validation({ code: 'barcode must be 8-14 digits' });
    }
    const hit = this.cache.get(code);
    if (hit && hit.expiresAt > Date.now()) return hit.view;

    const product = await this.fetchProduct(code);
    const view = this.mapProduct(code, product);
    this.cache.set(code, { view, expiresAt: Date.now() + this.cacheTtlMs });
    return view;
  }

  /** 调 OFF v2；任何失败（非 2xx / status!=1 / 超时 / 网络）归一为 NOT_FOUND */
  private async fetchProduct(code: string): Promise<Record<string, unknown>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await this.fetchFn(`${OFF_BASE_URL}/${encodeURIComponent(code)}.json`, {
        headers: { 'user-agent': USER_AGENT, accept: 'application/json' },
        signal: controller.signal,
      });
      if (!res.ok) throw err.barcodeNotFound();
      const body = (await res.json()) as {
        status?: number;
        product?: Record<string, unknown>;
      };
      if (body.status !== 1 || !body.product) throw err.barcodeNotFound();
      return body.product;
    } catch (e) {
      if ((e as { code?: string }).code === 'FOOD_BARCODE_NOT_FOUND') throw e;
      throw err.barcodeNotFound();
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * OFF product → 视图。能量优先取 `energy-kcal_100g`；OFF 部分商品只给
   * `energy-kj_100g`（或 `energy_100g` + energy_unit=kJ），按 4.184 kJ/kcal
   * 换算〔假设〕。名称/四营养任一缺失或越界 → 拒绝（NOT_FOUND）。
   */
  private mapProduct(code: string, product: Record<string, unknown>): BarcodeFoodView {
    const str = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
    const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : NaN);

    const generic = str(product.product_name);
    const nameZh = str(product.product_name_zh) || generic;
    const nameEn = str(product.product_name_en) || generic;
    if (!nameZh && !nameEn) throw err.barcodeNotFound();

    const nutriments = (product.nutriments ?? {}) as Record<string, unknown>;
    let kcal = num(nutriments['energy-kcal_100g']);
    if (Number.isNaN(kcal)) {
      const kJ = num(nutriments['energy-kj_100g'] ?? nutriments['energy_100g']);
      if (!Number.isNaN(kJ)) kcal = kJ / KJ_PER_KCAL;
    }
    const proteinG = num(nutriments.proteins_100g);
    const carbG = num(nutriments.carbohydrates_100g);
    const fatG = num(nutriments.fat_100g);
    const per100g = { kcal, proteinG, carbG, fatG };
    if ([kcal, proteinG, carbG, fatG].some(Number.isNaN)) {
      throw err.barcodeNotFound();
    }
    if (!isPer100gInRange(per100g)) throw err.barcodeNotFound();

    const round1 = (v: number) => Math.round(v * 10) / 10;
    return {
      id: `off_${code}`,
      barcode: code,
      nameZh: nameZh || nameEn, // 〔假设〕单语商品双语同名
      nameEn: nameEn || nameZh,
      aliases: [],
      kcalPer100g: round1(kcal),
      proteinPer100g: round1(proteinG),
      carbsPer100g: round1(carbG),
      fatPer100g: round1(fatG),
      source: 'openfoodfacts',
      isCustom: false,
    };
  }
}
