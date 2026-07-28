#!/usr/bin/env bash
# 拉取 USDA FoodData Central SR Legacy 公共数据集（无需 API key）到 raw/ 并解压。
# 数据源：https://fdc.nal.usda.gov/download-datasets （SR Legacy JSON zip）
set -euo pipefail
cd "$(dirname "$0")/.."

URL="https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2021-10-28.zip"
ZIP="raw/FoodData_Central_sr_legacy_food_json_2021-10-28.zip"
DIR="raw/sr_legacy"

mkdir -p raw "$DIR"
echo "[fetch] downloading $URL"
curl -fSL --retry 3 --max-time 600 -o "$ZIP" "$URL"
echo "[fetch] unzip -> $DIR"
unzip -o -q "$ZIP" -d "$DIR"
echo "[fetch] done: $(ls -lh "$DIR")"
