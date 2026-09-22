# eatwise_data — 食物营养库数据资产与导入管线（D-16）

中英双语食物营养库：《中国食物成分表 标准版（第6版）》机读衍生 + 人工策展中式
菜品/零食，每 100g 热量/蛋白/碳水/脂肪 + 中英别名。本目录是双端（server / app）
食物库数据的**唯一权威来源**，双端均从 `foods.seed.json` 导入。

产品口径（v1.13.10 起）：**中文用户优先，全库双语硬约束**——每条必须同时有
中文名与英文名（E4 校验强制）。无中文名的纯英文行（USDA SR Legacy 7283 条）
已从默认管线裁剪（中文用户搜不到、稀释搜索结果），`--include-usda` 可重新并入。

## 目录结构

```
eatwise_data/
├── foods.seed.json                 # 统一中间格式（管线产物，双端导入源）
├── raw/                            # USDA 原始数据集 + CFCT 源 CSV（可重拉）
│   ├── sr_legacy/*.json
│   └── cfct_food_composition_full.csv
├── cfct/
│   └── cfct_foods.json             # CFCT 转换产物（import_cfct.py 输出）
├── curated/
│   ├── zh_common_foods.json        # 人工策展中式高频食物（〔假设〕估值）
│   └── zh_dishes_snacks.json       # 中式菜品/零食扩充（gen_dishes_snacks.py 产物）
├── scripts/
│   ├── fetch_usda.sh               # 拉取 USDA SR Legacy（可选，默认裁剪）
│   ├── import_cfct.py              # CFCT CSV → cfct_foods.json（含 EN_BASE_NAMES 补译表）
│   ├── gen_dishes_snacks.py        # 策展菜品/零食生成（同名去重：旧行优先）
│   └── build_seed.py               # 汇总 + 对账 + 校验 + seed/报告 + 同步 App 资产
└── reports/
    └── validation_report.json      # 最近一次构建的质量校验报告
```

## 数据来源与许可（诚实声明）

| 来源 | 规模 | 许可 | 说明 |
|---|---|---|---|
| CFCT（cfct） | 1644 | **无开源许可证** | Sanotsu/china-food-composition-data（GitHub）——《中国食物成分表 标准版(第6版)》纸书截图 OCR 衍生机读数据，源仓库未标 license。按「个人学习数据、App 端内使用」口径使用；商用分发前需确认版权边界。营养值为成分表实测权威值。 |
| 策展（curated） | 314 | 自有 | `zh_common_foods.json` + `zh_dishes_snacks.json`，营养值为营养学常识**〔假设〕估值**，未经成分表逐条核对（`zh_verified=true` 仅表示条目经人工策展）；数值改动需同步 `docs/specs/规格-营养规则-TDEE公式与信号灯阈值-v1.0.md`。 |
| USDA SR Legacy（usda-sr） | 0（默认裁剪） | 公有领域 | 无中文名（中文用户搜不到），v1.13.10 起默认剔除；历史 id 全部计入 removedIds 由双端清残差。 |

CFCT 源数据中的 433 行 `englishName` 缺失（曾静默回退中文名，违反双语硬约束）——
由 `import_cfct.py` 的 `EN_BASE_NAMES`（202 基名人工审校译文）补齐；品牌/规格
后缀保留在中文名与别名中可搜。

## 数据字典（foods.seed.json）

顶层：`version`（管线版本号，内容变更需升级）、`generatedAt`、`sources`、`counts`、
`removedIds`、`foods[]`。

每条 food：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 稳定 slug，全局唯一。`cfct-<foodCode>` = 成分表；`curated-*` = 策展；`usda-<fdcId>` = USDA |
| `name_en` | string | 英文名（必填，**禁止含中文**，E4） |
| `name_zh` | string\|null | 中文名；纯英文来源为 null（默认管线已无此类行） |
| `aliases_zh` / `aliases_en` | string[] | 中文/英文别名（双语条目两者均须非空且语言正确） |
| `kcal` / `protein_g` / `carb_g` / `fat_g` | number | 每 100g 热量(kcal)/蛋白/碳水/脂肪(g) |
| `category` | string | 成分表大类 / 策展分类 |
| `source` | string | `cfct`（成分表实测）/ `curated`（人工策展〔假设〕）/ `usda-sr`（公共真实数据） |
| `zh_verified` | bool | 中文名/中文营养值是否经校对；curated 为 true 但营养值仍是〔假设〕估值 |

`removedIds`（**累计**清单）：历史版本出现过、当前版本已删除的行 id（同名对账
吸收、形态限定拆并、USDA 裁剪）。双端导入 upsert 后按它清残差——App 端
`FoodDao.deleteBuiltInByIds`（只删 isCustom=false 且未被 food_entries 引用的行），
服务端 prisma seed `updateMany` **软删** deletedAt（FoodEntry 外键无 onDelete，
硬删违约；内存驱动冷启动全量重建天然无残差）。清单只增不减，幂等可重放。

字段映射：
- 服务端 Prisma `Food`：`kcal→kcalPer100g`、`protein_g→proteinPer100g`、
  `carb_g→carbsPer100g`、`fat_g→fatPer100g`、`aliases_zh+aliases_en→aliases[]`。
  `name_zh` 为 null 时回退 `name_en`（schema 要求非空；i18n 规格：缺译有回退而非空白）。
- App drift `Foods`：同名字段映射；`aliases_zh/aliases_en` 以 JSON 字符串数组
  存入 `aliasesZh/aliasesEn` 列（LIKE 搜索直接匹配）；`name_zh` 为 null 时存空串。

## 同名对账（build_seed.py `reconcile_cfct_curated`）

同一食物在策展与 CFCT 各有一行时（旧 seed 双行并存=冗余）三分法：

1. **值近似（偏差 <30%）→ 吸收**：curated 行并入 cfct 行别名后出 seed
   （id 进 removedIds）；
2. **形态差（≥30%）→ 限定并存**：cfct 行加状态限定词（`CFCT_STATE_SUFFIX`，
   如 米粉(干/生) 349 vs 米粉〔熟〕108），基名留别名，两行语义不再混淆；
3. **CFCT 内部品种粒度**（栗子[板栗] 等）：有意保留，不并。

禁止用 CFCT 生/干值覆写 curated 熟态值（3 倍热量事故，v1.13.8 走查）。
生成侧（gen_dishes_snacks.py 同名即丢弃）+ 构建侧兜底双层防御；旧行优先
（已随旧 seed 出厂，删了造成双端残差）。

## 校验规则（build_seed.py 内置）

| 规则 | 级别 | 内容 |
|---|---|---|
| E1 | error | 四营养值非负 |
| E2 | error | id 全局唯一 |
| E3 | error | 双语条目（name_zh 非空）的中英别名均非空 |
| E4 | error | 双语条目 `name_en`/`aliases_en` 不得含中文（双语硬约束） |
| W1 | warning | kcal 与 4P+4C+9F 估算偏差 >20%（酒精/膳食纤维/糖醇可致合理偏差，仅报告不拦截） |

任何 error 使构建以非 0 退出；报告写入 `reports/validation_report.json`。

## 更新流程

```bash
# 1.（可选）重拉 CFCT 源 CSV → raw/（见 import_cfct.py 顶部 SRC_URL）
python3 scripts/import_cfct.py --csv raw/cfct_food_composition_full.csv

# 2. 增补策展数据：编辑 curated/zh_common_foods.json 或跑 gen_dishes_snacks.py
#    （每条需 id/name_zh/name_en/aliases_zh/aliases_en/四营养/category/zh_verified）

# 3. 重建 seed + 校验报告 + 同步 App 资产副本
python3 scripts/build_seed.py                  # 默认：cfct + curated（双语）
python3 scripts/build_seed.py --include-usda   # 并入 USDA（历史模式）

# 4. 升级版本号：修改 build_seed.py 顶部 SEED_VERSION（App 端按版本号幂等重导）
```

双端导入（均含 removedIds 清残差）：
- 服务端 PostgreSQL：`cd eatwise_server && npm run prisma:seed`（按 id upsert +
  removedIds 软删，幂等；部署流水线 migrate 后自动执行）。
- 服务端内存 DataStore（无数据库开发模式）：`npm run start:dev` 启动时自动加载
  （`src/common/store/food-seed-loader.ts`；冷启动全量重建，天然无残差）。
- App：启动 `FoodSeedLoader.ensureSeeded()`（`lib/core/storage/food_seed_loader.dart`）
  把 `assets/foods/foods.seed.json` 灌入 drift，按版本号幂等 + prune。

## 规模现状（2026-09-22 构建，版本 2026.09.22）

- **总计 1958 条，双语 1958（100%）**：CFCT 1644 + 策展 314。
- 收敛清单 removedIds=7326（同名吸收 43 + USDA 裁剪 7283）。
- 校验：0 error；46 条 W1 warning。
- 搜索实测：drift 全库四列 LIKE 全表扫描 <7ms（无需 FTS 索引）。

## 双语运营口径

E4 使「无中文名/英文名为中文」的行无法出厂。USDA 若重新并入需先补中文名
（`--include-usda` 仅数据保留手段，不是发布形态）；策展扩充走
`curated/`，营养值改动必须同步营养规则规格文档并〔待营养背书〕标注。
