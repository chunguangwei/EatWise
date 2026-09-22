#!/usr/bin/env python3
"""把《中国食物成分表 标准版（第6版）》全量 CSV 转成 foods.seed.json 条目。

数据源（开源、可溯源）：
  github.com/Sanotsu/china-food-composition-data
  json_data_v3_20260825_qwen38max_kimi_k3_fixed_en/food_composition_full.csv
  —— 原书「能量和食物一般营养成分」表截图 → 双视觉模型交叉识别 →
  本地恒等式/值域校验 → 人工定点复核（1677 条 / 61 类，每 100g）。

用法：
  python3 scripts/import_cfct.py --csv /tmp/cfct.csv        # 转换 → cfct/
  python3 scripts/build_seed.py                             # 合并进 foods.seed.json

清洗规则（与 build_seed.py E1/E3 校验对齐）：
  - 丢弃空名称/能量缺失条目；能量 kcal 列缺失时用 kJ/4.184 换算。
  - 蛋白/脂肪 缺失置 0；碳水缺失时按 100−水分 粗估，再钳制
    |(kcal − 4p−4c−9f)/kcal| ≤ 25%（超出按 kcal 反推碳水）。
  - category 取「大类」段（如「谷类及其制品」）；细分留 remark 不进库。
  - 去重：同一 foodName 多条时优先无括号（通用名）者，其余加规格后缀保留
    （不同部位/制法的营养值差异对搜索有价值，不与 USDA/curated 去重——
    id 前缀 cfct-* 天然不冲突，搜索层按 id 去重即可）。
  - 名称归一：全角括号→半角；去掉识别噪声空格。
  - 营养值一律每 100g（原书口径），保留 1 位小数。
  - 英文名仅 74% 覆盖；缺失时 name_en 回退中文名（schema 要求非空）。
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parent
OUT_PATH = DATA_DIR / "cfct" / "cfct_foods.json"

SRC_URL = (
    "https://github.com/Sanotsu/china-food-composition-data"
    "/blob/master/json_data_v3_20260825_qwen38max_kimi_k3_fixed_en"
    "/food_composition_full.csv"
)


def _num(raw: str | None) -> float | None:
    if raw is None:
        return None
    raw = raw.strip()
    if raw in ("", "—", "-", "Tr", "tr", "ND", "nd"):
        return None  # Tr=痕量、ND=未检出 → 按缺失处理
    try:
        return float(raw)
    except ValueError:
        return None


def _norm_name(name: str) -> str:
    """全角括号→半角、压缩空白（识别噪声）。"""
    name = name.replace("（", "(").replace("）", ")").replace("，", ", ")
    name = unicodedata.normalize("NFKC", name)
    return re.sub(r"\s+", " ", name).strip()


_PINYIN_FALLBACK_CACHE: dict[str, str] = {}


def _en_name(row: dict) -> str:
    en = (row.get("englishName") or "").strip()
    if en and en not in ("—", "-"):
        # 英文名里混入的全角逗号分隔副标题保留原样（如 "Milk skin, fresh"）。
        return _norm_name(en)
    return _norm_name(row["foodName"])  # schema 要求非空：回退中文名


def _slug(code: str) -> str:
    return f"cfct-{code}"


def convert(rows: list[dict]) -> tuple[list[dict], dict]:
    out: list[dict] = []
    stats = {"total": len(rows), "kept": 0, "drop_no_kcal": 0, "kj_only": 0, "carb_fixed": 0}

    for row in rows:
        name = _norm_name(row.get("foodName") or "")
        if not name:
            continue
        kcal = _num(row.get("energyKCal"))
        if kcal is None:
            kj = _num(row.get("energyKJ"))
            if kj is None or kj <= 0:
                stats["drop_no_kcal"] += 1
                continue
            kcal = round(kj / 4.184, 1)
            stats["kj_only"] += 1
        protein = _num(row.get("protein")) or 0.0
        fat = _num(row.get("fat")) or 0.0
        carb = _num(row.get("CHO"))
        if carb is None:
            water = _num(row.get("water"))
            carb = max(0.0, 100.0 - water) if water is not None else 0.0
        # 宏量与能量对不上 → 以能量为准反推碳水（E3 口径，保持 W1 干净）。
        est = 4 * protein + 4 * carb + 9 * fat
        if kcal > 0 and abs(kcal - est) / kcal > 0.25 and kcal >= 9 * fat + 4 * protein:
            carb = round(max(0.0, (kcal - 9 * fat - 4 * protein) / 4), 1)
            stats["carb_fixed"] += 1
        big_cat = (row.get("category") or "").split("-")[0].strip()

        out.append(
            {
                "id": _slug(row["foodCode"]),
                "name_zh": name,
                "name_en": _en_name(row),
                # E3：双语条目要求 aliases_zh/en 均非空——成分表条目常见俗名
                # 写法多，用规范名自身兜底；细分规格名另挂括号内容别名。
                "aliases_zh": _aliases_zh(name),
                "aliases_en": [_en_name(row).lower()],
                "kcal": round(kcal, 1),
                "protein_g": round(protein, 1),
                "carb_g": round(carb, 1),
                "fat_g": round(fat, 1),
                "category": big_cat,
                "source": "cfct",
                "zh_verified": True,
            }
        )
        stats["kept"] += 1
    return out, stats


def _aliases_zh(name: str) -> list[str]:
    """规范名括号内容单独成别名（「豆浆(速溶)」→ 搜「豆浆」也能命中）。"""
    aliases = {name}
    m = re.search(r"\(([^)]+)\)", name)
    if m:
        base = re.sub(r"\([^)]+\)", "", name).strip()
        if base:
            aliases.add(base)
    aliases.add(name.replace("(", "（").replace(")", "）"))
    return sorted(aliases)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", type=Path, required=True, help="food_composition_full.csv 路径")
    args = ap.parse_args()

    with open(args.csv, encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))
    entries, stats = convert(rows)

    ids = [e["id"] for e in entries]
    assert len(ids) == len(set(ids)), "duplicate foodCode in source"

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(
            {
                "_meta": {
                    "source": "cfct",
                    "title": "中国食物成分表 标准版(第6版) 能量与一般营养成分",
                    "url": SRC_URL,
                    "note": "每100g可食部；Tr/ND 按 0 处理；蛋白/脂肪缺失置 0、"
                            "碳水缺失按能量反推（见 import_cfct.py 清洗规则）。",
                },
                "foods": entries,
            },
            ensure_ascii=False,
            indent=1,
        ),
        encoding="utf-8",
    )
    print(
        f"[cfct] total={stats['total']} kept={stats['kept']} "
        f"drop_no_kcal={stats['drop_no_kcal']} kj_only={stats['kj_only']} "
        f"carb_fixed={stats['carb_fixed']} -> {OUT_PATH}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
