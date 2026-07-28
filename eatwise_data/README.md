# eatwise_data — 食物营养库数据资产与导入管线（D-16）

MVP 自建核心食物库：基于《中国食物成分表》理念 + USDA FoodData Central 公共数据，
中英双语条目，每 100g 热量/蛋白/碳水/脂肪 + 别名。本目录是双端（server / app）
食物库数据的**唯一权威来源**，双端均从 `foods.seed.json` 导入。

## 目录结构

```
eatwise_data/
├── foods.seed.json                 # 统一中间格式（管线产物，双端导入源）
├── raw/                            # USDA 原始数据集（zip + 解压产物，可重拉）
│   └── sr_legacy/*.json
├── curated/
│   └── zh_common_foods.json        # 人工策展中式高频食物（172 条，〔假设〕估值）
├── scripts/
│   ├── fetch_usda.sh               # 拉取 USDA SR Legacy 公共数据集（无需 API key）
│   └── build_seed.py               # 转换 + 校验 + 输出 seed/报告 + 同步 App 资产
└── reports/
    └── validation_report.json      # 最近一次构建的质量校验报告
```

## 数据字典（foods.seed.json）

顶层：`version`（管线版本号，内容变更需升级）、`generatedAt`、`sources`、`counts`、`foods[]`。

每条 food：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 稳定 slug，全局唯一。`curated-*` = 策展；`usda-<fdcId>` = USDA |
| `name_en` | string | 英文名（必填） |
| `name_zh` | string\|null | 中文名；USDA 未翻译条目为 null |
| `aliases_zh` / `aliases_en` | string[] | 中文/英文别名（双语条目两者均须非空） |
| `kcal` / `protein_g` / `carb_g` / `fat_g` | number | 每 100g 热量(kcal)/蛋白/碳水/脂肪(g) |
| `category` | string | USDA foodCategory 或策展分类 |
| `source` | string | `usda-sr`（公共真实数据）/ `curated`（人工策展） |
| `zh_verified` | bool | 中文名/中文营养值是否经校对。curated 目前为 true（已人工策展）但营养值仍是〔假设〕估值；USDA 条目一律 false |

字段映射：
- 服务端 Prisma `Food`：`kcal→kcalPer100g`、`protein_g→proteinPer100g`、
  `carb_g→carbsPer100g`、`fat_g→fatPer100g`、`aliases_zh+aliases_en→aliases[]`。
  `name_zh` 为 null 时回退 `name_en`（schema 要求非空；i18n 规格：缺译有回退而非空白）。
- App drift `Foods`：同名字段映射；`aliases_zh/aliases_en` 以 JSON 字符串数组
  存入 `aliasesZh/aliasesEn` 列（LIKE 搜索直接匹配）；`name_zh` 为 null 时存空串。

## 校验规则（build_seed.py 内置）

| 规则 | 级别 | 内容 |
|---|---|---|
| E1 | error | 四营养值非负 |
| E2 | error | id 全局唯一 |
| E3 | error | 双语条目（name_zh 非空）的中英别名均非空 |
| W1 | warning | kcal 与 4P+4C+9F 估算偏差 >20%（USDA 数据允许酒精/膳食纤维/糖醇造成的合理偏差，仅报告不拦截） |

任何 error 使构建以非 0 退出；报告写入 `reports/validation_report.json`。

## 更新流程

```bash
# 1. 拉取/更新 USDA 原始数据（SR Legacy JSON zip，无需 API key）
bash scripts/fetch_usda.sh

# 2. 增补策展数据：编辑 curated/zh_common_foods.json
#    （每条需 id/name_zh/name_en/aliases_zh/aliases_en/四营养/category/zh_verified）

# 3. 重建 seed + 校验报告 + 同步 App 资产副本
python3 scripts/build_seed.py            # 全量（USDA + 策展）
python3 scripts/build_seed.py --skip-usda  # 仅策展（无原始数据时的样本模式）

# 4. 升级版本号：修改 build_seed.py 顶部 SEED_VERSION（App 端按版本号幂等重导）
```

双端导入：
- 服务端 PostgreSQL：`cd eatwise_server && npm run prisma:seed`（按 id upsert，幂等）。
- 服务端内存 DataStore（无数据库开发模式）：`npm run start:dev` 启动时自动加载
  （`src/common/store/food-seed-loader.ts`）。
- App：首次启动 `FoodSeedLoader.ensureSeeded()`（`lib/core/storage/food_seed_loader.dart`）
  把 `assets/foods/foods.seed.json` 灌入 drift，按版本号幂等。

## 规模现状（2026-07-28 构建，版本 2026.07.1）

- **总计 7455 条**：USDA SR Legacy **7283 条**（公共真实数据，已过滤 Baby Foods 与
  American Indian/Alaska Native Foods 两个非通用类目）+ 人工策展 **172 条**。
- 双语条目（有中文名）：**172 条**（全部为策展条目）。
- 校验：0 error；410 条 W1 warning（USDA 酒精/膳食纤维导致的 kcal 估算偏差，仅报告）。

**诚实声明**：策展条目的营养值为营养学常识**〔假设〕估值**，未经《中国食物成分表》
逐条核对（该表无公开机读数据源，未伪造来源）；`zh_verified=true` 仅表示条目经人工
策展，不表示营养值已校对，上线前需营养侧复核。

## 达到 D-16 目标（≥3000 条双语）的数据运营计划

当前双语条目 172 条，距 3000 条缺口约 2800 条。存量 7283 条 USDA 条目为英文
（`name_zh=null`、`zh_verified=false`），双端均已按「回退英文名 + 英文别名可搜」
处理，不出现空白。补足计划：

1. **高频优先翻译**：按 USDA 类目 + 中式饮食高频词表，先翻 ~1500 条高频条目
   （谷薯、肉蛋奶、蔬果、常见加工食品），机翻初稿 → 人工校对，校对后置
   `zh_verified=true`、补 `aliases_zh`。
2. **策展扩充**：`zh_common_foods.json` 从 172 条扩到 ~500 条（家常菜、外卖高频、
   地方主食），营养值请注册营养师按《中国食物成分表》纸版/授权数据核对后去除
   〔假设〕标注。
3. **翻译校对流程**：译稿进 `curated/translations/<batch>.json`（新建）→
   build_seed.py 合并（后续迭代）→ 校验 E3 强制别名非空 → 双人复核后
   `zh_verified=true`；未校对条目保持 `zh_verified=false`，UI 可标注「翻译待确认」。
4. **验收口径**：`counts.bilingual >= 3000` 且 `zh_verified_true >= 3000`，
   validation_report 0 error 方可发布版本。
