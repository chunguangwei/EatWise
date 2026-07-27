# 《规格-营养规则-TDEE 公式与信号灯阈值》v1.0

> 本文档是《产品需求评审》「必须解决」项 3 的落地规格，依据决策记录 **D-04 / D-05** 展开，供客户端（Flutter 双端）、后端与测试三方共同执行。
> **整体状态：〔待外部确认：营养专业侧书面背书〕** —— 依据 D-04/D-05 的决策状态「待外部背书，开发可并行」：本文全部规则**可先按本文开发并行推进**，但 M4（营养可视化分析）上线前必须取得营养专业侧对 TDEE 公式、活动系数、营养素配比与红黄绿阈值的**书面背书**；背书若调整数值，仅通过服务端热配置（见第 6 章）变更，不改代码逻辑。
> 关联文档：PRD v1.0（M1/M4）、《产品需求评审》、《决策记录》（D-04/D-05/D-15/D-17/D-20）。

---

## 文档信息

| 项 | 内容 |
|----|------|
| 文档名称 | 规格-营养规则-TDEE 公式与信号灯阈值 |
| 版本 | v1.0 |
| 状态 | 〔待外部确认：营养专业侧书面背书〕（开发可并行） |
| 决策依据 | D-04（每日营养目标公式）、D-05（红黄绿信号灯阈值） |
| 适用范围 | iOS / Android（Flutter 单代码库，D-17）+ 服务端配置 |
| 撰写日期 | 2026-07-27 |

### 术语与记号

| 术语 | 含义 |
|------|------|
| BMR | 基础代谢率（kcal/日），Mifflin-St Jeor 公式估算 |
| TDEE | 每日总能量消耗（kcal/日）= BMR × 活动系数 |
| 目标热量 | 按用户目标（减脂/维持）折算后的每日热量目标（kcal） |
| 完成率 p | 当日某营养素累计摄入 ÷ 当日目标 × 100%，**判定用未取整原始值**，展示用四舍五入整数〔假设〕 |
| 落区 | 完成率落入的信号灯区间：绿（green）/ 黄（yellow）/ 红（red） |

---

## 一、TDEE 计算纯函数完整规格（D-04）

### 1.1 输入模型

| 字段 | 类型 | 单位 | 必填 | 说明 |
|------|------|------|------|------|
| `sex` | enum: `male` / `female` | — | 是（缺失走兜底，见 1.6） | 生理性别，仅用于公式 |
| `age` | int | 岁 | 是 | 取值域 [10, 100]，域外视为缺失走兜底〔假设〕 |
| `heightCm` | double | cm | 是 | 取值域 [100, 250]，域外视为缺失〔假设〕 |
| `weightKg` | double | kg | 是 | 取值域 [25, 300]，域外视为缺失〔假设〕；取最近一次体重记录 |
| `activityLevel` | enum | — | 是 | `sedentary` / `light` / `moderate` / `high`，见 1.3 |
| `goal` | enum | — | 是 | `lose`（减脂）/ `maintain`（维持/作息/先试试看） |

### 1.2 BMR：Mifflin-St Jeor 公式（D-04）

- 男：`BMR = 10 × weightKg + 6.25 × heightCm − 5 × age + 5`
- 女：`BMR = 10 × weightKg + 6.25 × heightCm − 5 × age − 161`

计算全程使用浮点，**中间结果不取整**。

### 1.3 活动系数表（D-04）

| `activityLevel` | 系数 | 用户侧文案（问卷选项） |
|-----------------|------|------------------------|
| `sedentary` 久坐 | 1.2 | 大部分时间是坐着的（办公室/居家，几乎不运动） |
| `light` 轻度 | 1.375 | 每周轻度运动 1–3 次（散步、瑜伽等） |
| `moderate` 中度 | 1.55 | 每周中等强度运动 3–5 次（跑步、游泳等） |
| `high` 高度 | 1.725 | 每周高强度运动 6 次以上或体力劳动者 |

### 1.4 目标热量与下限保护（D-04）

| `goal` | 公式 | 下限保护 |
|--------|------|----------|
| `lose` 减脂 | `targetKcal = TDEE × 0.8` | **女 ≥ 1200 kcal；男 ≥ 1500 kcal**：折算结果低于下限则取下限值 |
| `maintain` 维持/作息/先试试看 | `targetKcal = TDEE × 1.0` | 无需触发（TDEE 必然高于下限，但仍保留同一保护逻辑统一执行）〔假设〕 |

**取整规则〔假设〕**：`targetKcal` 四舍五入到 **10 kcal**（如 1211.04 → 1210）用于存储与展示；判定与营养素克数换算均基于取整后的 `targetKcal`。

### 1.5 输出模型

```
NutritionGoal {
  bmr: double            // 原始值，仅调试/专业数据展开区使用
  tdee: double           // 原始值
  targetKcal: int        // 取整到 10 kcal 的每日热量目标
  proteinG: int          // 见第二章换算
  carbG: int
  fatG: int
  usedFallback: bool     // 是否走了 1.6 兜底（驱动补全引导）
  configVersion: string  // 计算所用配置版本号，见 6.3（埋点与回溯用）
}
```

### 1.6 缺基础信息的兜底默认值与补全引导（D-04）

- 触发条件：`sex / age / heightCm / weightKg / activityLevel / goal` 任一缺失或越域（1.1）。
- 兜底值：**女 1800 kcal / 男 2200 kcal**；`sex` 也缺失时按 **2000 kcal**（两值均值）〔假设〕。按第 2 章同配比折算三大营养素，`usedFallback = true`。
- 兜底时不计算/不展示 BMR 与 TDEE 原始值。
- **补全引导**（`usedFallback = true` 时）：
  - 数据页顶部与「我的-目标」页展示引导条：中文「补全身高体重，营养目标会更准哦 🌱」/ 英文「Add your height & weight for more accurate goals 🌱」（品牌语气：鼓励而非命令，见设计稿 2.4）。
  - 点击跳转资料补全页；补全后**当日即重算**目标，已摄入数据保留，信号灯按新目标重判。
  - 引导条可关闭，关闭后 7 天内不再展示〔假设〕。
- 用户资料更新（体重变化等）：目标**实时重算并即时生效**，历史日的目标快照不回溯修改（见 7.3）〔假设〕。

### 1.7 纯函数接口（Dart，Flutter 双端共用，D-17）

```dart
/// 纯函数：无 I/O、无时钟依赖、无副作用；同输入必同输出。
/// config 来自服务端热配置（第 6 章），不允许在函数内读取全局状态。
NutritionGoal computeNutritionGoal(UserProfileInput input, NutritionRuleConfig config);

/// 信号灯判定纯函数：p 为完成率（未取整），nutrient 指定用哪组阈值。
SignalZone classify(double p, NutrientType nutrient, NutritionRuleConfig config);
```

---

## 二、三大营养素配比与 kcal→g 换算（D-04）

### 2.1 配比与换算系数

| 营养素 | 供能占比 | 换算系数 | 克数公式 | 取整〔假设〕 |
|--------|----------|----------|----------|--------------|
| 蛋白质 protein | 25% | 4 kcal/g | `targetKcal × 0.25 ÷ 4` | 四舍五入到 1 g |
| 碳水 carb | 45% | 4 kcal/g | `targetKcal × 0.45 ÷ 4` | 四舍五入到 1 g |
| 脂肪 fat | 30% | 9 kcal/g | `targetKcal × 0.30 ÷ 9` | 四舍五入到 1 g |

### 2.2 完整计算示例 A：28 岁女，55 kg / 162 cm，久坐，减脂

| 步骤 | 计算 | 结果 |
|------|------|------|
| BMR | `10×55 + 6.25×162 − 5×28 − 161 = 550 + 1012.5 − 140 − 161` | 1261.5 kcal |
| TDEE | `1261.5 × 1.2`（久坐） | 1513.8 kcal |
| 减脂目标 | `1513.8 × 0.8 = 1211.04`；下限检查：1211.04 ≥ 1200 ✓ | 1211.04 kcal |
| 取整 | 四舍五入到 10 kcal | **targetKcal = 1210 kcal** |
| 蛋白质 | `1210 × 0.25 ÷ 4 = 75.625` | **76 g** |
| 碳水 | `1210 × 0.45 ÷ 4 = 136.125` | **136 g** |
| 脂肪 | `1210 × 0.30 ÷ 9 = 40.33` | **40 g** |

> 边界验证：若该用户为 160 cm / 50 kg，则 BMR = 1151.5，TDEE = 1381.8，×0.8 = 1105.44 < 1200 → **触发下限保护，targetKcal = 1200**。

### 2.3 完整计算示例 B：24 岁男，75 kg / 176 cm，轻度，维持

| 步骤 | 计算 | 结果 |
|------|------|------|
| BMR | `10×75 + 6.25×176 − 5×24 + 5 = 750 + 1100 − 120 + 5` | 1735 kcal |
| TDEE | `1735 × 1.375`（轻度） | 2385.625 kcal |
| 维持目标 | `2385.625 × 1.0`；下限检查：≥ 1500 ✓ | 2385.625 kcal |
| 取整 | 四舍五入到 10 kcal | **targetKcal = 2390 kcal** |
| 蛋白质 | `2390 × 0.25 ÷ 4 = 149.375` | **149 g** |
| 碳水 | `2390 × 0.45 ÷ 4 = 268.875` | **269 g** |
| 脂肪 | `2390 × 0.30 ÷ 9 = 79.67` | **80 g** |

---

## 三、红黄绿信号灯阈值（D-05 全表）

### 3.1 阈值表（闭区间写法，边界归属唯一）

判定量：完成率 `p = 当日累计摄入 ÷ 当日目标 × 100`（**未取整原始值**参与比较〔假设〕，展示时四舍五入为整数百分比）。区间记法：`[a,b)` 含 a 不含 b。

| 营养素 | 🔴 红（警示） | 🟡 黄（提醒） | 🟢 绿（达标） |
|--------|---------------|---------------|---------------|
| 热量 kcal | `[0,60) ∪ (130,+∞)` | `[60,85) ∪ (110,130]` | `[85,110]` |
| 蛋白质 protein | `[0,70) ∪ (150,+∞)` | `[70,90)` | `[90,150]` |
| 碳水 carb | `[0,65) ∪ (135,+∞)` | `[65,85) ∪ (115,135]` | `[85,115]` |
| 脂肪 fat | `[0,55) ∪ (130,+∞)` | `[55,80) ∪ (110,130]` | `[80,110]` |

**边界值归属规则**（与 D-05「85%–110%」等表述的等价闭区间化）：

- 绿区两端为**闭端点**：如热量 p=85.0、p=110.0 均为绿。
- 绿→黄上边界开、黄→红上边界闭：如热量 p∈(110,130] 为黄，p=130.0 为黄，p>130 才为红。
- 低侧对称：p<60 为红，p=60.0 为黄，p=85.0 为绿。
- 蛋白质独有「过量标红」：p=150.0 仍为绿，p>150 标红并提示「蛋白质有点多啦」（D-05）。
- 实现约束：比较一律用 `<` / `<=` 按上表区间判定，**禁止**先对 p 取整再比较（避免 84.6→85 误判为绿）。

### 3.2 当日无数据规则

- 当日（本地自然日）无任何 `FoodEntry` → **不显示任何信号灯**，数据页/首页 mini 卡显示空状态引导：中文「肚子的故事还没写呢，点橙色按钮记一笔？」/ 英文「No meals logged yet — tap the orange button to add your first bite.」（承接设计稿空状态文案，鼓励语气）。
- 部分营养素为 0（如只记了食物但脂肪为 0）：该营养素按 p=0 判定（通常落红区低侧），但**建议文案使用「还没记到」语义而非「超标」语义**，见第 4 章模板。
- 有记录但该日目标因兜底而未个性化：信号灯正常显示，同时展示 1.6 的补全引导条。

### 3.3 呈现硬性要求

- 三重编码（颜色 + 图标 + 文字）为 P0 硬性要求（PRD M8 / 设计稿）：绿 ✓ / 黄 ! / 红 手形（hand-up），色值 `--signal-green #3DBE8B` / `--signal-yellow #FFD24C` / `--signal-red #FF6B6B`，绝不单靠颜色。
- 语义固定全局一致：绿=达标、黄=适量/提醒、红=警示，不混用（设计稿 2.2）。

---

## 四、一句话建议规则模板库（D-05）

### 4.1 生成机制

- MVP 使用**规则模板库**，不用模型生成（D-05）。维度：**营养素(4) × 落区(红黄绿) × 餐段(早/午/晚/加餐)**。
- 模板分两层：**基础模板**（营养素 × 落区，12 条中文 + 12 条英文，见 4.2）+ **餐段变体片段**（4 餐段，见 4.3）。生成时将基础模板中的 `{meal_action}` 占位符替换为当前/下一餐段的片段。
- 餐段判定〔假设〕：按本地时间 05:00–10:00 早、10:00–15:00 午、15:00–21:00 晚、21:00–次日 05:00 加餐；建议指向「当前所处或下一个」餐段。
- 语气：鼓励而非命令、简单而非术语（设计稿 2.4）；禁用「必须/禁止/RDA/低于推荐值」等措辞；允许轻量 emoji。
- 文案全部走 i18n key（D-15），命名规则：`advice.{nutrient}.{zone}` 与 `advice.meal.{meal}`。

### 4.2 基础模板：营养素 × 落区（中英各 12 条）

| # | 营养素 | 落区 | 中文模板 | 英文模板 |
|---|--------|------|----------|----------|
| 1 | 热量 | 绿 | 今天热量刚刚好，节奏很稳，继续保持～ 🌱 | Your calories are right on track today — nice and steady, keep it up! 🌱 |
| 2 | 热量 | 黄-低 | 今天吃得有点少，{meal_action}，身体会感谢你的。 | You're a bit under on calories — {meal_action}. Your body will thank you. |
| 3 | 热量 | 黄-高 | 热量有一点点高，{meal_action}，就回来啦。 | Calories are a touch high — {meal_action} and you're right back on track. |
| 4 | 热量 | 红-低 | 今天摄入太少了，断食之外也要好好吃饭哦，{meal_action}。 | You're well under today — outside your fasting window, do eat well: {meal_action}. |
| 5 | 热量 | 红-高 | 热量小超啦，别焦虑，{meal_action}，明天又是新的一天。 | A bit over on calories — no stress! {meal_action}. Tomorrow's a fresh day. |
| 6 | 蛋白质 | 绿 | 蛋白质满分！肌肉群给你比心 💪 | Protein nailed it! Your muscles are sending you a heart 💪 |
| 7 | 蛋白质 | 黄 | 蛋白质还差一点，{meal_action}，就够啦。 | Protein is almost there — {meal_action} and you've got it. |
| 8 | 蛋白质 | 红-低 | 今天蛋白质有点少 🟡 {meal_action}，给身体加点料。 | Protein's on the low side today — {meal_action} to give your body a boost. |
| 9 | 蛋白质 | 红-高 | 蛋白质有点多啦，{meal_action}，均衡一点更舒服。 | A little much protein today — {meal_action} for a comfier balance. |
| 10 | 碳水 | 绿 | 碳水刚刚好，能量供应稳稳的。 | Carbs are just right — steady energy all the way. |
| 11 | 碳水 | 黄-低 | 碳水略少，{meal_action}，下午不容易犯困哦。 | Carbs are a bit low — {meal_action} to keep the afternoon slump away. |
| 12 | 碳水 | 红-高 | 碳水超得有点多，{meal_action}，让血糖稳一点。 | Carbs ran quite high — {meal_action} to keep your blood sugar steadier. |

> 脂肪（fat）行因表宽折列如下，编号连续：

| # | 营养素 | 落区 | 中文模板 | 英文模板 |
|---|--------|------|----------|----------|
| 13 | 脂肪 | 绿 | 脂肪摄入很健康，皮肤和气色都会喜欢。 | Healthy fat intake — your skin and glow will love it. |
| 14 | 脂肪 | 黄-低 | 好脂肪有点少，{meal_action}，帮助吸收维生素。 | Good fats are a bit low — {meal_action}; they help absorb vitamins. |
| 15 | 脂肪 | 红-高 | 脂肪有点高了，{meal_action}，清淡一点更轻盈。 | Fat's on the high side — {meal_action} for a lighter feel. |

> 说明：热量/碳水/脂肪的「黄」区在实现上拆为黄-低、黄-高两条 key；蛋白质「红」拆为红-低、红-高。落区到 key 的映射由规则引擎完成，模板消费方不感知方向判断。上表共 15 条中文 + 15 条英文，满足「各 ≥12 条」并覆盖 4 营养素 × 3 落区（含方向细分）。

### 4.3 餐段变体片段（`{meal_action}` 取值）

| 餐段 | 中文片段 | 英文片段 |
|------|----------|----------|
| 早 breakfast | 早餐加个鸡蛋或一杯豆浆 | add an egg or a glass of soy milk at breakfast |
| 午 lunch | 午餐来份掌心大的瘦肉或豆腐 | go for a palm-size portion of lean meat or tofu at lunch |
| 晚 dinner | 晚餐选清蒸/白灼，七分饱就好 | pick something steamed or lightly poached for dinner, and stop at 80% full |
| 加餐 snack | 加餐来把坚果或一杯酸奶 | grab a handful of nuts or a yogurt as a snack |

组合示例（早餐段、蛋白质黄）：中文「蛋白质还差一点，早餐加个鸡蛋或一杯豆浆，就够啦。」/ EN "Protein is almost there — add an egg or a glass of soy milk at breakfast and you've got it."

### 4.4 特殊语义规则

- 当日该营养素摄入 = 0 且有记录：低侧红/黄文案改用「还没记到」语义，如中文「好像还没记到蛋白质哦，是不是漏了一餐？」/ EN "No protein logged yet — did a meal slip by?"〔假设：每种营养素各备 1 条零摄入专用文案，key：`advice.{nutrient}.zero`〕。
- 文案变更走服务端热配置（第 6 章）随模板版本下发，不发版即可改文案。

---

## 五、规则引擎技术要求

### 5.1 总体架构

- **纯函数**：`computeNutritionGoal` 与 `classify` 均为纯函数（1.7），无 I/O、无时钟、无全局状态；单元测试可直接构造输入断言输出。
- 客户端与服务端共用同一份规则参数（热配置 JSON），客户端本地计算（离线可用，D-20 本地优先），服务端在聚合接口返回时**重算校验**一次，不一致以服务端为准并上报埋点〔假设〕。
- 语言实现：客户端 Dart（Flutter 单代码库，iOS/Android 完全同一份代码，无双端逻辑分叉）；服务端 Node.js/NestJS（D-17）实现同函数供校验与后台聚合使用，两侧共用同一份 JSON 配置与同一组黄金测试用例（5.2 表可作为 fixtures）。

### 5.2 必须覆盖的单测用例清单

| 分组 | # | 用例 | 预期 |
|------|---|------|------|
| BMR | U1 | 示例 A（女 28/55/162） | BMR = 1261.5 |
| BMR | U2 | 示例 B（男 24/75/176） | BMR = 1735 |
| BMR | U3 | 男女公式常数项（+5 / −161）不串用 | 同参数换性别结果不同 |
| TDEE | U4 | 四个活动系数 1.2/1.375/1.55/1.725 逐一映射 | 与 1.3 表一致 |
| TDEE | U5 | activityLevel 缺失 | 走兜底，usedFallback=true |
| 目标 | U6 | 减脂 ×0.8（示例 A） | 1211.04 → 1210 |
| 目标 | U7 | 减脂触发女下限 1200（160cm/50kg 久坐） | targetKcal = 1200 |
| 目标 | U8 | 减脂触发男下限 1500（构造低体重用例） | targetKcal = 1500 |
| 目标 | U9 | 维持 ×1.0（示例 B） | 2390 |
| 取整 | U10 | 目标热量四舍五入到 10 kcal 的边界（如 ×x4.9→x0, x5.0→x0 或 x0+10 按四舍五入验证） | 与 1.4 规则一致 |
| 配比 | U11 | 示例 A 三营养素 | 76/136/40 g |
| 配比 | U12 | 示例 B 三营养素 | 149/269/80 g |
| 兜底 | U13 | 缺身高 → 女 1800 / 男 2200；缺性别 → 2000 | 与 1.6 一致 |
| 兜底 | U14 | 越域输入（age=5、height=400）按缺失处理 | 走兜底 |
| 兜底 | U15 | 兜底时按同配比折算克数 | 1800→P113/C203/F60；2200→P138/C248/F73 |
| 阈值 | U16 | 热量边界：p=59.99 红、60.0 黄、84.99 黄、85.0 绿、110.0 绿、110.01 黄、130.0 黄、130.01 红 | 与 3.1 闭区间一致 |
| 阈值 | U17 | 蛋白质边界：69.99 红、70.0 黄、90.0 绿、150.0 绿、150.01 红 | 同上 |
| 阈值 | U18 | 碳水边界：65.0/85.0/115.0/135.0 四点归属 | 同上 |
| 阈值 | U19 | 脂肪边界：55.0/80.0/110.0/130.0 四点归属 | 同上 |
| 阈值 | U20 | p 不预取整：p=84.6 必须判黄（不得因四舍五入变绿） | 黄 |
| 无数据 | U21 | 当日 0 条 FoodEntry → 不产出信号灯 | 返回空态标记 |
| 零摄入 | U22 | 有记录但脂肪=0 → 红-低 + zero 文案 key | `advice.fat.zero` |
| 模板 | U23 | 4 营养素 × 3 落区 × 4 餐段全部 key 存在且中英双语非空 | i18n 完整性 |
| 模板 | U24 | 文案扫描：不含「必须/禁止/RDA」等违禁词 | 品牌语气合规 |
| 配置 | U25 | 配置版本回退：本地缓存版本新于服务端时用本地；schema 校验失败时用内置默认配置 | 降级可用 |
| 一致性 | U26 | 黄金用例集（U1–U22 输入输出）在 Dart 与 Node 两侧跑同 fixtures，结果全等 | 双端一致 |

### 5.3 公式与阈值服务端热配置

**配置结构 JSON Schema**（Draft 2020-12）：

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "NutritionRuleConfig",
  "type": "object",
  "required": ["version", "tdee", "macroRatio", "fallback", "thresholds", "adviceTemplateVersion"],
  "properties": {
    "version": { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$", "description": "语义化版本号，如 1.0.0" },
    "tdee": {
      "type": "object",
      "required": ["activityFactors", "loseDeficit", "minKcal", "roundingStepKcal"],
      "properties": {
        "activityFactors": {
          "type": "object",
          "properties": {
            "sedentary": { "const": 1.2 },
            "light": { "const": 1.375 },
            "moderate": { "const": 1.55 },
            "high": { "const": 1.725 }
          }
        },
        "loseDeficit": { "type": "number", "const": 0.8 },
        "minKcal": {
          "type": "object",
          "properties": {
            "female": { "const": 1200 },
            "male": { "const": 1500 }
          }
        },
        "roundingStepKcal": { "const": 10 }
      }
    },
    "macroRatio": {
      "type": "object",
      "properties": {
        "protein": { "const": 0.25 },
        "carb": { "const": 0.45 },
        "fat": { "const": 0.30 }
      },
      "description": "三者之和必须 = 1.0，服务端发布时校验"
    },
    "fallback": {
      "type": "object",
      "properties": {
        "femaleKcal": { "const": 1800 },
        "maleKcal": { "const": 2200 },
        "unknownKcal": { "const": 2000 }
      }
    },
    "thresholds": {
      "type": "object",
      "required": ["kcal", "protein", "carb", "fat"],
      "properties": {
        "kcal":     { "$ref": "#/$defs/zone" },
        "protein":  { "$ref": "#/$defs/zone" },
        "carb":     { "$ref": "#/$defs/zone" },
        "fat":      { "$ref": "#/$defs/zone" }
      }
    },
    "adviceTemplateVersion": { "type": "string", "description": "模板库版本，指向 i18n 文案包" }
  },
  "$defs": {
    "zone": {
      "type": "object",
      "required": ["greenLow", "greenHigh", "yellowLow", "yellowHigh", "redHigh", "redLowOver"],
      "properties": {
        "greenLow":  { "type": "number", "description": "绿区下界（含）" },
        "greenHigh": { "type": "number", "description": "绿区上界（含）" },
        "yellowLow": { "type": "number", "description": "黄-低下界（含），低于此即红-低" },
        "yellowHigh":{ "type": "number", "description": "黄-高上界（含），高于此即红-高" },
        "redHigh":   { "type": "number", "description": "红-高触发值（不含），如 130" },
        "redLowOver":{ "type": ["number", "null"], "description": "过量标红触发值（不含），仅蛋白质用 150，其余为 null" }
      }
    }
  }
}
```

`thresholds` 默认值（对应 3.1）：

| 营养素 | greenLow | greenHigh | yellowLow | yellowHigh | redHigh | redLowOver |
|--------|----------|-----------|-----------|------------|---------|------------|
| kcal | 85 | 110 | 60 | 130 | 130 | null |
| protein | 90 | 150 | 70 | 90(黄-高不存在，置 null 语义见注) | — | 150 |
| carb | 85 | 115 | 65 | 135 | 135 | null |
| fat | 80 | 110 | 55 | 130 | 130 | null |

> 注：蛋白质无「黄-高」区，`yellowHigh` 置 null，`classify` 对该营养素跳过黄-高分支。schema 中各 `const` 值即 D-04/D-05 拍板值；营养侧背书后若调整，仅改配置升版本号，不改代码。

**版本与发布**：

- `version` 语义化：背书修订升 minor（如 1.0.0→1.1.0），文案调整升 `adviceTemplateVersion`，结构性变更升 major 并强制客户端最低版本检查。
- 客户端启动与每 24h 拉取一次配置，本地持久化缓存；拉取失败/校验失败用缓存，缓存也没有用内置默认配置（U25）。
- **灰度发布方式**：服务端配置带 `rollout` 元信息（百分比 0–100 + 白名单 userId 列表），按 userId 哈希分桶；默认 5% → 25% → 100% 三档，每档观察 ≥24h 的核心指标（信号灯点击异常反馈率、目标重算报错率）；支持一键回滚到上一版本，回滚即时生效〔假设：复用 D-20 同步通道下发配置，无需单独配置中心〕。
- 每次计算输出的 `configVersion` 写入 DailyNutrition 与埋点，保证任何判定可回溯到具体配置版本。

### 5.4 双端（iOS / Android）差异说明

- **计算逻辑：无差异**。Flutter 单代码库（D-17），同一 Dart 实现跑双端；禁止任何平台条件分支进入规则引擎。
- 展示层差异仅限于：数字/日期本地化格式（i18n，D-15：小数点/千分位随系统 locale）、系统字体回退（iOS 苹方 / Android 思源黑体，设计稿 2.3）——不影响数值本身。
- 浮点一致性：Dart 在 iOS/Android 均为 IEEE 754 double，比较前不做平台相关取整；U26 双端黄金用例保证一致。
- 「日」的边界：聚合按**设备本地时区自然日**（与 D-07 的 UTC 存储 + 本地渲染原则一致），双端均用本地时区，无平台差异。

---

## 六、与数据模型的映射：DailyNutrition 聚合逻辑

### 6.1 数据流

```
FoodEntry（含营养快照，PRD M3）──按日累加──▶ DailyNutrition ──classify──▶ 信号灯 + 一句话建议
                                        ▲
              NutritionGoal（第一章纯函数输出，随 configVersion 记录）
```

### 6.2 FoodEntry 营养快照

- 每条 `FoodEntry` 落库时写入**营养快照**（不可变）：`kcal / proteinG / carbG / fatG`，按「食物库每 100g 值 × 份量 g ÷ 100」在录入时算定（PRD 数据模型）。
- 快照在确认入账时即固定：食物库后续修订**不回溯**修改历史快照（保证历史日数据可解释）〔假设〕。

### 6.3 DailyNutrition 聚合规则

| 字段 | 来源 / 逻辑 |
|------|-------------|
| `userId, date` | `date` = 设备本地时区自然日（FoodEntry.datetime UTC 转本地后归属） |
| `totalKcal / totalProteinG / totalCarbG / totalFatG` | 当日全部 `FoodEntry` 快照字段**逐项求和**；条目撤销（D-11）或删除后立即从累计中扣除并重算 |
| `targetKcal / targetProteinG / targetCarbG / targetFatG` | 当日起始时的 NutritionGoal **快照**；当日中途补全资料/更新体重导致目标变化时，当日改用新目标并记录 `goalUpdatedAt`，历史日不回溯（1.6）〔假设〕 |
| `zones` | `{kcal, protein, carb, fat}` 各自落区，由 `classify` 产出 |
| `adviceKeys` | 当日展示的 i18n key 列表（随 zones + 餐段生成） |
| `hasData` | 当日 FoodEntry 数 > 0；false 时前端不渲染信号灯（3.2） |
| `configVersion` | 判定所用配置版本号 |

- **重算触发点**：新增/撤销/删除 FoodEntry、目标重算（资料补全）、配置版本升级（仅当日及以后生效，历史日保留原判定）〔假设〕。
- **同步**：DailyNutrition 为派生数据，本地可重算，随 D-20 四态持久化同步；冲突时以「重新聚合」解决而非字段级 LWW——服务端收到 FoodEntry 终态后重算该日 DailyNutrition 并下发〔假设〕。
- 饮水、体重记录（PRD M3 轻量项）**不参与** DailyNutrition 聚合。

---

## 七、验收标准汇总（可测试）

| # | 验收点 | 依据 |
|---|--------|------|
| A1 | 示例 A/B 计算结果与本文 2.2/2.3 完全一致 | D-04 |
| A2 | 下限保护：女 <1200 取 1200、男 <1500 取 1500 | D-04 |
| A3 | 缺信息兜底 1800/2200/2000 + 补全引导条展示与 7 天关闭期 | D-04 |
| A4 | 3.1 全部边界值（U16–U20）判定正确，p 不预取整 | D-05 |
| A5 | 当日无记录不显示信号灯、显示空状态引导 | D-05 / PRD M4 |
| A6 | 信号灯三重编码（颜色+图标+文字）齐全 | PRD M8 |
| A7 | 建议模板 4×3×4 全覆盖，中英各 ≥12 条，无违禁词（U23/U24） | D-05 / D-15 |
| A8 | 配置热更新不改代码即可调阈值；灰度 5%→25%→100% 与回滚可用 | 评审项 3 |
| A9 | 单测清单 5.2 全部通过；Dart/Node 黄金用例一致（U26） | 评审项 3 |
| A10 | 营养专业侧书面背书取得后，本文状态由〔待外部确认〕转为定稿 | 评审项 3 / D-04 |

---

## 附：〔假设〕与〔待外部确认〕清单

| 标注 | 内容 | 位置 |
|------|------|------|
| 〔待外部确认〕 | 全文规则（公式/系数/配比/阈值）需营养专业侧书面背书，M4 上线 Gate | 全文（D-04/D-05） |
| 〔假设〕 | p 判定用未取整原始值，展示取整 | 1.0/3.1 |
| 〔假设〕 | 输入取值域（年龄 10–100 等） | 1.1 |
| 〔假设〕 | 目标热量取整到 10 kcal、克数取整到 1 g | 1.4/2.1 |
| 〔假设〕 | sex 缺失兜底 2000 kcal；引导条关闭 7 天不重复；目标实时重算历史不回溯 | 1.6 |
| 〔假设〕 | 餐段时间划分（05–10/10–15/15–21/21–05） | 4.1 |
| 〔假设〕 | 零摄入专用文案 `advice.{nutrient}.zero` | 4.4 |
| 〔假设〕 | 服务端重算校验不一致以服务端为准并埋点 | 5.1 |
| 〔假设〕 | 灰度复用 D-20 同步通道，不设独立配置中心 | 5.3 |
| 〔假设〕 | FoodEntry 快照不回溯；DailyNutrition 冲突以重聚合解决；目标快照当日切换 | 6.2/6.3 |
