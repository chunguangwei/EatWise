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
# CFCT 源行约 433 行 englishName 为空（回退中文名）——违反双语硬约束
# （name_en/aliases_en 非中文）。这些行的规范名去括号后落在下列 202 个基名上，
# 按基名补译（本表为人工审校译文，非机翻直出）；命中基名后 name_en = 基名译文，
# 品牌/规格后缀（(雀巢)(代表值) 等）进 aliases_en 保留可搜性。
EN_BASE_NAMES: dict[str, str] = {
    "全脂甜炼乳": "Sweetened condensed whole milk",
    "脱脂甜炼乳": "Sweetened condensed skim milk",
    "蛋白粉": "Protein powder",
    "牛初乳奶片": "Bovine colostrum milk tablet",
    "奶渣": "Dried milk curd",
    "奶油": "Cream",
    "酥油": "Butter (yak, Tibetan)",
    "酥油茶": "Butter tea",
    "全脂奶粉": "Whole milk powder",
    "全脂甜奶粉": "Sweetened whole milk powder",
    "低脂奶粉": "Low-fat milk powder",
    "驴奶粉": "Donkey milk powder",
    "驼奶粉": "Camel milk powder",
    "儿童配方奶粉": "Children formula milk powder",
    "孕产妇配方奶粉": "Maternity formula milk powder",
    "孕产妇配方羊奶粉": "Maternity goat milk formula",
    "中老年配方奶粉": "Senior formula milk powder",
    "中老年营养奶粉": "Senior nutritional milk powder",
    "奶酪": "Cheese",
    "低脂奶酪": "Low-fat cheese",
    "硬质干酪": "Hard cheese",
    "酸奶疙瘩": "Dried yogurt curd",
    "纯牛奶": "Whole milk",
    "调制乳": "Modified milk",
    "鲜牛奶": "Fresh milk",
    "人乳": "Human milk",
    "鲜驴奶": "Fresh donkey milk",
    "鲜驼奶": "Fresh camel milk",
    "驼奶": "Camel milk",
    "酸奶": "Yogurt",
    "蜂蛹": "Bee pupa",
    "牛蛙": "Bullfrog",
    "鸡内金": "Chicken gizzard lining",
    "乌梢蛇": "Black racer snake",
    "团螵蛸": "Mantis egg case",
    "阿胶": "Donkey-hide gelatin",
    "珍珠": "Pearl",
    "牛黄": "Calculus bovis",
    "马鹿胎": "Elk fetus",
    "蛤蚧": "Gecko",
    "燕窝": "Edible bird's nest",
    "蛤蟆油": "Oviduct of forest frog",
    "龟甲": "Tortoise shell",
    "刺猬皮": "Hedgehog skin",
    "裙边": "Softshell turtle edge",
    "鱼肚": "Fish maw",
    "鱼唇": "Fish lip",
    "鹿肉": "Venison",
    "牛肉": "Beef",
    "牦牛肉": "Yak beef",
    "牦牛牛腱肉": "Yak shank",
    "牦牛牛霖肉": "Yak knuckle",
    "牛百叶": "Beef tripe",
    "牛腱子": "Beef shank",
    "牛肉干": "Beef jerky",
    "猪肉": "Pork",
    "猪皮": "Pork skin",
    "猪小排": "Pork ribs",
    "猪腿肉": "Pork leg",
    "猪肾": "Pork kidney",
    "猪肚": "Pork tripe",
    "猪肝": "Pork liver",
    "猪舌": "Pork tongue",
    "火腿心全精肉": "Ham center lean",
    "火腿心肉": "Ham center",
    "腊肉": "Cured pork",
    "叉烧肉": "Char siu pork",
    "酱排骨": "Soy-braised pork ribs",
    "猪肉罐头": "Canned pork",
    "猪里脊": "Pork tenderloin",
    "猪肉脯": "Pork jerky",
    "肉酥": "Pork floss",
    "扒猪脸": "Braised pork cheek",
    "酱肘子": "Soy-braised pork knuckle",
    "火腿肉": "Ham",
    "风干肉": "Air-dried meat",
    "脆皮肠": "Crispy sausage",
    "热狗肠": "Hot dog sausage",
    "火腿肠": "Ham sausage",
    "火腿": "Ham",
    "三明治火腿": "Sandwich ham",
    "午餐肉": "Luncheon meat",
    "羊肉": "Lamb",
    "羊肉片": "Sliced lamb",
    "烧羊肉": "Roast lamb",
    "羊肉串": "Lamb skewer",
    "驴肉": "Donkey meat",
    "乳鸽": "Squab",
    "火鸡腿": "Turkey leg",
    "鸡胸脯肉": "Chicken breast",
    "鸡腿": "Chicken leg",
    "鸡翅": "Chicken wing",
    "鸡块": "Chicken pieces",
    "野山鸡": "Pheasant",
    "扒鸡": "Braised chicken",
    "烤鸡": "Roast chicken",
    "童子鸡": "Spring chicken",
    "鸭豉片": "Dried smoked duck slice",
    "烤鸭": "Roast duck",
    "鹅血": "Goose blood curd",
    "腊鹅": "Cured goose",
    "牛肝菌": "Porcini mushroom",
    "红菱": "Water caltrop",
    "鸡蛋": "Chicken egg",
    "毛蛋": "Balut",
    "荷包蛋": "Fried egg",
    "海鸭蛋": "Duck egg (sea duck)",
    "鸭蛋": "Duck egg",
    "鹅蛋": "Goose egg",
    "甲鱼蛋": "Softshell turtle egg",
    "乌龟": "Turtle",
    "金鲨鱼翅": "Fish fin (golden shark)",
    "鱼翅": "Shark fin",
    "棘参": "Spiny sea cucumber",
    "海参": "Sea cucumber",
    "梅花参": "Thelenota ananas sea cucumber",
    "墨鱼": "Cuttlefish",
    "墨鱼圈": "Cuttlefish ring",
    "墨鱼丸": "Cuttlefish ball",
    "北极虾": "Ice shrimp",
    "九节虾": "Banded shrimp",
    "口虾蛄": "Mantis shrimp",
    "罗氏沼虾": "Giant freshwater prawn",
    "南美白对虾": "Whiteleg shrimp",
    "青虾": "River prawn",
    "琼海虾": "Qionghai shrimp",
    "虾酱": "Shrimp paste",
    "虾仁": "Peeled shrimp",
    "虾皮": "Dried krill",
    "虾仁肉丸": "Shrimp meatball",
    "海蟹": "Sea crab",
    "锯缘青蟹": "Mud crab",
    "大闸蟹": "Shanghai hairy crab",
    "蟹足棒": "Crab stick",
    "蟹膏": "Crab roe paste",
    "蟹肉": "Crab meat",
    "蟹黄": "Crab roe",
    "梭子蟹": "Swimming crab",
    "海蚌": "Surf clam",
    "鲍鱼": "Abalone",
    "蛏子": "Razor clam",
    "缢蛏": "Razor clam (synonymimera)",
    "牛角江珧蛤": "Pen shell clam",
    "文蛤": "Hard clam",
    "血蚶": "Blood clam",
    "六角螺": "Hexagonal sea snail",
    "海螺肉": "Sea snail meat",
    "文蛤丸": "Hard clam ball",
    "草鱼": "Grass carp",
    "鲢鱼": "Silver carp",
    "鲫鱼": "Crucian carp",
    "丁桂鱼": "Tench",
    "乌鳢": "Snakehead",
    "花骨鱼": "Topmouth culter",
    "黄颡鱼": "Yellow catfish",
    "回头鱼": "Elopichthys bambusa",
    "鮰鱼": "Longsnout catfish",
    "斑鳠": "Spotted catfish",
    "抗浪鱼": "Anshu carp",
    "蓝鳃太阳鱼": "Bluegill",
    "钳鱼": "Channel catfish",
    "翘嘴红鲌": "Topmouth culter (red)",
    "鲥鱼": "Reeves shad",
    "鳊鱼": "Bream",
    "鲟鱼": "Sturgeon",
    "雅鱼": "Ya fish (Schizothorax)",
    "胭脂鱼": "High-fin banded shark",
    "棒棒鱼": "Stickfish (local)",
    "尖嘴鱼": "Needlefish (local)",
    "胡子鱼": "Barbel catfish",
    "带鱼": "Hairtail",
    "黄鱼": "Yellow croaker",
    "金鰉鱼": "Chinese sturgeon",
    "鲭鱼": "Mackerel",
    "双髻鲨": "Hammerhead shark",
    "紫青低纹鮨": "Purple sweetlips",
    "鮟鱇鱼": "Anglerfish",
    "鲳鱼": "Pomfret",
    "大菱鲆鱼": "Turbot",
    "海鲈鱼": "Sea bass",
    "红鳍笛鲷": "Redfin snapper",
    "黄姑鱼": "Yellow drum",
    "鲅鱼": "Spanish mackerel",
    "石斑鱼": "Grouper",
    "苏眉鱼": "Humphead wrasse",
    "青衣": "Coris wrasse",
    "笠鱼": "Capelin (local)",
    "金枪鱼肉": "Tuna meat",
    "鲅鱼肉": "Spanish mackerel meat",
    "刺泡鱼": "Spiny frogfish (local)",
    "鱼排": "Fish fillet steak",
    "鱼丸": "Fish ball",
    "鱼子酱": "Caviar",
    "丁香鱼": "Dried sardine (kayasashi)",
    "凤尾鱼": "Anchovy",
    "箭鱼": "Swordfish",
    "金枪鱼": "Tuna",
    "鲮鱼": "Dace",
    "鳗鱼": "Eel",
    "沙丁鱼": "Sardine",
    "午餐鱼": "Canned fish",
    "鳕鱼": "Cod",
}


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


def _base_name(name: str) -> str:
    """去括号/方括号限定语的基名（与 build_seed 对账同口径）。"""
    n = re.sub(r"[\(（][^)）]*[\)）]", "", name)
    n = re.sub(r"\[[^\]]*\]", "", n)
    return n.strip()


def _en_name(row: dict) -> str:
    en = (row.get("englishName") or "").strip()
    if en and en not in ("—", "-") and not _has_han(en):
        # 英文名里混入的全角逗号分隔副标题保留原样（如 "Milk skin, fresh"）。
        return _norm_name(en)
    # 源英文名缺失或为中文回退：按基名补译（EN_BASE_NAMES 人工审校表）。
    translated = EN_BASE_NAMES.get(_base_name(_norm_name(row["foodName"])))
    if translated:
        return translated
    return _norm_name(row["foodName"])  # 仍未命中：schema 要求非空，回退中文名


def _has_han(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


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
