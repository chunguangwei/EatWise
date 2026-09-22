#!/usr/bin/env python3
"""EatWise 食物库构建管线（D-16）。

输入：
  - raw/sr_legacy/*.json            USDA SR Legacy 公共数据集（fetch_usda.sh 拉取）
  - curated/zh_common_foods.json    人工策展中式高频食物（source: curated，〔假设〕估值）
输出：
  - foods.seed.json                 统一中间格式（对齐双端 Food 模型）
  - reports/validation_report.json  质量校验报告（errors/warnings）
  - ../eatwise_app/assets/foods/foods.seed.json  App 端资产同步副本

校验规则（见 README 数据字典）：
  E1 四营养值非负                    → error
  E2 id 全局唯一                     → error
  E3 双语条目（name_zh 非空）别名非空 → error（aliases_zh/aliases_en 均须 ≥1）
  W1 kcal 与 4P+4C+9F 偏差 >20%      → warning（USDA 允许酒精/膳食纤维偏差，仅报告）
任何 error 导致退出码非 0。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parent
REPO_ROOT = DATA_DIR.parent

SEED_VERSION = "2026.09.22"
USDA_GLOB = "raw/sr_legacy/*.json"
CURATED_PATH = DATA_DIR / "curated" / "zh_common_foods.json"
CFCT_PATH = DATA_DIR / "cfct" / "cfct_foods.json"
SEED_PATH = DATA_DIR / "foods.seed.json"
REPORT_PATH = DATA_DIR / "reports" / "validation_report.json"
APP_ASSET_PATH = REPO_ROOT / "eatwise_app" / "assets" / "foods" / "foods.seed.json"

# USDA 营养素编号（SR Legacy foodNutrients[].nutrient.number）
N_PROTEIN, N_CARB, N_FAT, N_KCAL = "203", "205", "204", "208"

# 非通用食物类目：对核心高频库无价值，直接过滤
EXCLUDED_CATEGORIES = {
    "Baby Foods",
    "American Indian/Alaska Native Foods",
}

KCAL_TOLERANCE = 0.20  # W1 阈值


def usda_entries(raw_path: Path) -> list[dict]:
    doc = json.loads(raw_path.read_text(encoding="utf-8"))
    out: list[dict] = []
    for food in doc["SRLegacyFoods"]:
        category = (food.get("foodCategory") or {}).get("description", "")
        if category in EXCLUDED_CATEGORIES:
            continue
        amounts: dict[str, float] = {}
        for fn in food.get("foodNutrients", []):
            num = str((fn.get("nutrient") or {}).get("number", ""))
            if num in (N_PROTEIN, N_CARB, N_FAT, N_KCAL) and fn.get("amount") is not None:
                amounts[num] = float(fn["amount"])
        kcal = amounts.get(N_KCAL)
        if kcal is None:
            continue  # 无热量数据，无导入价值
        name_en = food["description"].strip()
        out.append(
            {
                "id": f"usda-{food['fdcId']}",
                "name_en": name_en,
                "name_zh": None,
                "aliases_en": [name_en.lower()] if name_en else [],
                "aliases_zh": [],
                "kcal": kcal,
                "protein_g": amounts.get(N_PROTEIN, 0.0),
                "carb_g": amounts.get(N_CARB, 0.0),
                "fat_g": amounts.get(N_FAT, 0.0),
                "category": category,
                "source": "usda-sr",
                "zh_verified": False,
            }
        )
    return out


def curated_entries() -> list[dict]:
    foods: list[dict] = []
    for path in sorted((DATA_DIR / "curated").glob("*.json")):
        foods.extend(json.loads(path.read_text(encoding="utf-8"))["foods"])
    return foods


def cfct_entries() -> list[dict]:
    """《中国食物成分表 第6版》全量（scripts/import_cfct.py 预转换产物）。

    文件缺失静默跳过（CI 无 raw 数据时同样不受影响）。"""
    if not CFCT_PATH.exists():
        print("[build] WARNING: cfct/cfct_foods.json not found, skipping", file=sys.stderr)
        return []
    doc = json.loads(CFCT_PATH.read_text(encoding="utf-8"))
    return doc["foods"]


# ── cfct × curated 同名对账 ──────────────────────────────────────────────
# 成分表条目常为 生/干 态（米粉 dried, raw ≈349），curated 同名常为 熟/即食 态
# （≈108）。两行并存 = 搜「米粉」双命中不同值，用户误点生态行 = 3 倍热量事故。
# 口径（v1.13.10，走查 advisory）：
#   · 偏差 <30% → 值近似，curated 冗余行吸收进 cfct 行（别名并入，curated 行出 seed）；
#   · 偏差 ≥30% → 两种形态都有价值，两行并存，但 cfct 行加状态限定词消歧
#     （米粉→米粉(干/生)），基名保留在 aliases 里搜单名照样命中。
# 限定词依据 = 成分表行内证据（englishName 的 dried/raw/flour/roasted/whole、
# 同组分脂肪含量），不伪造原书副标题。key 为 cfct foodCode（=id 后缀）。
CFCT_STATE_SUFFIX = {
    "012410": "干/生",  # Rice noodle, dried, raw
    "012411": "干/生",  # Rice noodle, flattened, dried, raw
    "019010": "干",  # Buckwheat flour, refined
    "122206": "干/制品",  # 虾仁 199kcal 远超生鲜虾 ~85（本行碳水 27.7 → 裹粉干制）
    "031529": "油炸/香",  # 豆腐干 427kcal、脂肪 35.2g/100g
    "082303": "干",  # Beef, dried（名字已含干，保留原名只吸收语义，不改写）
    "092301": "整只带皮",  # Beijing white duck, roasted, whole（带皮整只热量远高于去皮）
}
CFCT_ABSORB_THRESHOLD = 0.30


def reconcile_cfct_curated(cfct: list[dict], curated: list[dict]) -> tuple[set[str], list[dict]]:
    """同名对账：返回（应出 seed 的 curated id 集，对账日志）。原地修改 cfct 行。"""
    by_name: dict[str, list[dict]] = {}
    for e in cfct:
        if e.get("name_zh"):
            by_name.setdefault(e["name_zh"], []).append(e)
    removed: set[str] = set()
    log: list[dict] = []
    for c in curated:
        name = c.get("name_zh")
        if not name or name not in by_name:
            continue
        for cf in by_name[name]:
            dev = (
                abs(c["kcal"] - cf["kcal"]) / max(c["kcal"], cf["kcal"])
                if max(c["kcal"], cf["kcal"]) > 0
                else 0.0
            )
            if dev < CFCT_ABSORB_THRESHOLD:
                # 近似同值：curated 行出 seed，别名全部并入 cfct 行。
                removed.add(c["id"])
                merged = dict.fromkeys([*cf["aliases_zh"], *c["aliases_zh"], name])
                cf["aliases_zh"] = sorted(merged)
                cf["aliases_en"] = sorted(
                    dict.fromkeys([*cf["aliases_en"], *c["aliases_en"], c["name_en"].lower()])
                )
                log.append({"name": name, "action": "absorb", "cfct": cf["id"],
                            "curated": c["id"], "dev": round(dev, 3)})
            else:
                # 形态差异：两行并存，cfct 行加状态限定词（幂等：已有括号不重复加）。
                suffix = CFCT_STATE_SUFFIX.get(cf["id"].removeprefix("cfct-"))
                if suffix and "(" not in cf["name_zh"]:
                    cf["name_zh"] = f"{name}({suffix})"
                    cf["aliases_zh"] = sorted({*cf["aliases_zh"], name})
                    log.append({"name": name, "action": "qualify", "cfct": cf["id"],
                                "as": cf["name_zh"], "dev": round(dev, 3)})
    return removed, log


def slug_free(entries: list[dict]) -> list[dict]:
    """规整数值（保留 1 位小数），其余字段原样。"""
    for e in entries:
        for k in ("kcal", "protein_g", "carb_g", "fat_g"):
            e[k] = round(float(e[k]), 1)
    return entries


def validate(entries: list[dict]) -> tuple[list[dict], list[dict]]:
    errors: list[dict] = []
    warnings: list[dict] = []
    seen: dict[str, int] = {}
    for e in entries:
        fid = e["id"]
        if fid in seen:
            errors.append({"rule": "E2", "id": fid, "msg": "duplicate id"})
        seen[fid] = seen.get(fid, 0) + 1
        for k in ("kcal", "protein_g", "carb_g", "fat_g"):
            if e[k] < 0:
                errors.append({"rule": "E1", "id": fid, "msg": f"{k} negative: {e[k]}"})
        if e.get("name_zh"):
            if not e.get("aliases_zh") or not e.get("aliases_en"):
                errors.append(
                    {"rule": "E3", "id": fid, "msg": "bilingual entry missing aliases"}
                )
            # 双语硬约束：有中文名的条目，英文名/英文别名必须非中文
            # （CFCT 源 433 行 englishName 缺失曾静默回退中文名）。
            def _han(v):
                return isinstance(v, str) and any("\u4e00" <= ch <= "\u9fff" for ch in v)
            if _han(e.get("name_en")) or any(_han(a) for a in e.get("aliases_en", [])):
                errors.append(
                    {"rule": "E4", "id": fid, "msg": "bilingual entry name_en/aliases_en contains Chinese"}
                )
        estimated = 4 * e["protein_g"] + 4 * e["carb_g"] + 9 * e["fat_g"]
        if e["kcal"] > 0 and estimated > 0:
            dev = abs(e["kcal"] - estimated) / e["kcal"]
            if dev > KCAL_TOLERANCE:
                warnings.append(
                    {
                        "rule": "W1",
                        "id": fid,
                        "kcal": e["kcal"],
                        "est_4_4_9": round(estimated, 1),
                        "deviation": round(dev, 3),
                        "msg": "kcal deviates from 4P+4C+9F by >20% "
                        "(USDA: alcohol/fiber/sugar-alcohol may legitimately cause this)",
                    }
                )
    return errors, warnings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--include-usda", action="store_true",
                    help="并入 USDA SR Legacy 英文行（默认剔除：产品口径中文优先，"
                         "7283 行无中文名条目中文用户搜不到，且稀释搜索结果）")
    ap.add_argument("--raw", type=Path, default=None, help="指定 USDA JSON 路径（默认 glob raw/sr_legacy/*.json）")
    args = ap.parse_args()

    started = time.time()
    entries: list[dict] = curated_entries()
    cfct = cfct_entries()
    slug_free(cfct)
    slug_free(entries)
    absorbed, recon_log = reconcile_cfct_curated(cfct, entries)
    entries = [e for e in entries if e["id"] not in absorbed]
    entries.extend(cfct)
    usda_count = 0
    usda_path = args.raw
    if args.include_usda:
        if usda_path is None:
            hits = sorted(DATA_DIR.glob(USDA_GLOB))
            usda_path = hits[0] if hits else None
        if usda_path and usda_path.exists():
            usda = usda_entries(usda_path)
            usda_count = len(usda)
            entries.extend(usda)
        else:
            print("[build] WARNING: USDA raw data not found, curated-only mode", file=sys.stderr)

    # slug_free 已就地执行
    errors, warnings = validate(entries)

    curated_count = len(entries) - usda_count - len(cfct)
    zh_count = sum(1 for e in entries if e.get("name_zh"))
    # 收敛清单：对比上一版 seed 的 id 集 → removedIds（累计并集，幂等可
    # 重放）。无条件并入 prev.removedIds——同版本重跑也必须保留历史累计，
    # 否则清残差链条断裂。
    removed_ids: list[str] = []
    if SEED_PATH.exists():
        try:
            prev = json.loads(SEED_PATH.read_text(encoding="utf-8"))
            new_ids = {e["id"] for e in entries}
            stale = [f["id"] for f in prev.get("foods", []) if f["id"] not in new_ids]
            removed_ids = sorted(set(prev.get("removedIds", [])) | set(stale) | absorbed)
        except (json.JSONDecodeError, OSError, KeyError):
            print("[build] WARNING: previous seed unreadable, removedIds starts empty",
                  file=sys.stderr)

    report = {
        "seedVersion": SEED_VERSION,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "counts": {
            "total": len(entries),
            "usda-sr": usda_count,
            "cfct": len(cfct),
            "curated": curated_count,
            "bilingual": zh_count,
            "zh_verified_true": sum(1 for e in entries if e.get("zh_verified")),
        },
        "reconcile": recon_log,
        "removedIds": removed_ids,
        "errors": errors,
        "warnings": warnings,
        "warningSummary": {"W1_kcal_deviation_gt_20pct": len(warnings)},
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if errors:
        print(f"[build] FAILED: {len(errors)} validation errors, see {REPORT_PATH}", file=sys.stderr)
        return 1

    seed = {
        "version": SEED_VERSION,
        "generatedAt": report["generatedAt"],
        "sources": (
            ["curated"] + (["cfct"] if cfct else []) + (["usda-sr"] if usda_count else [])
        ),
        "note": "cfct = 《中国食物成分表 标准版(第6版)》每100g 实测权威值；"
        "USDA SR Legacy = 公共真实数据；curated = 人工策展〔假设〕估值，待营养侧校对。"
        "removedIds = 历史版本出现过、当前版本已删除的行 id，导入方按它清残差。",
        "counts": report["counts"],
        "removedIds": removed_ids,
        "foods": entries,
    }
    SEED_PATH.write_text(json.dumps(seed, ensure_ascii=False), encoding="utf-8")
    APP_ASSET_PATH.parent.mkdir(parents=True, exist_ok=True)
    APP_ASSET_PATH.write_text(json.dumps(seed, ensure_ascii=False), encoding="utf-8")

    print(
        f"[build] OK in {time.time()-started:.1f}s: total={len(entries)} "
        f"(usda-sr={usda_count}, curated={curated_count}, bilingual={zh_count}), "
        f"absorbed={len(absorbed)}, qualified={sum(1 for r in recon_log if r['action']=='qualify')}, "
        f"removedIds={len(removed_ids)}, warnings={len(warnings)} -> {SEED_PATH}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
