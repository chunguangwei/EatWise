/** 每 100g 营养（自定义食物防腐校验 + 条码 OFF 数据校验共用） */
export interface Per100g {
  kcal: number;
  proteinG: number;
  carbG: number;
  fatG: number;
}

/**
 * 每 100g 营养合理区间（自定义食物 + 条码数据防腐共用）。
 * 〔假设〕kcal ≤900 覆盖纯油脂上限；三大营养素单项 ≤100g。
 */
export function isPer100gInRange(p: Per100g): boolean {
  const macro = (v: number) => Number.isFinite(v) && v >= 0 && v <= 100;
  return (
    Number.isFinite(p.kcal) &&
    p.kcal >= 0 &&
    p.kcal <= 900 &&
    macro(p.proteinG) &&
    macro(p.carbG) &&
    macro(p.fatG)
  );
}
