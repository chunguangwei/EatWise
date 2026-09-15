# UI/UX 走查报告 — v1.2.1（Android，2026-09-15）

- **构建**：main @ 86edfb7（v1.2.1，版本号 1.2.1 (15)），debug APK，`API_BASE_URL=http://10.0.2.2:3000/v1`
- **环境**：AVD eatwise_test（Android 36 arm64，系统语言 English）；后端内存模式；账号 walktest02
- **截图**：`/tmp/ui_walkthrough/ux-*.png`
- **范围**：新功能（端侧小模型/生效链路卡/估算徽标）+ 全页面 UX 过检 + 中英文案 + 暗色主题 + 英文复验。只记录不改代码。

---

## 一、新功能验证

### 1. 生效链路卡（Estimate routing）✅

- 都未配 → 高亮「3. Cloud fallback — Always available / Active」（ux-06）。
- 下载完成后未启用 → row 1 显示 Disabled，仍高亮云端兜底（ux-33）。
- 开启「Prefer on-device estimates」→ row 1「Enabled / Active」高亮（ux-34）。
- 关闭端侧 + 配置 Custom API → row 2「Configured / Active」高亮（ux-40）。
- 三级优先级与高亮逻辑全部符合预期。

### 2. 端侧小模型五态 ✅（模拟器真实下载 2.41GB 完成）

| 状态 | 证据 | 结论 |
|---|---|---|
| 未下载 | ux-06（Download model 按钮 + 2.41GB/Wi-Fi 提示） | ✅ |
| 下载中 | ux-07/08/26/29/32（进度条 + 百分比 0→94%，切页面下载不断） | ✅ |
| 已暂停 | ux-09（Cancel →「Paused (7% downloaded)」+ Resume + Delete model） | ✅ |
| 已就绪 | ux-33（「Model ready」+ 首次估算加载提示 + 启用开关 + Delete model） | ✅ |
| 错误 | 未覆盖（未模拟断网/校验失败） | ➖ |

- **下载实测**：ModelScope 源，模拟器约 2.4MB/s，0%→94% 约 25 分钟（中间切页面/切语言不中断）。
- **估算实测**：自定义食物「Mooncake」端侧估算约 5-10s（含首次加载模型），结果 350kcal/10/50/15，带 sanity 区间，数值量级合理。

### 3. 估算徽标 ✅（三态中两态实测，一态为后端 stub 所限）

- **端侧估算**：「On-device estimate — please confirm」橙条（ux-35）✅
- **自定义 API 估算**：自建 OpenAI 兼容 mock（GET /models + POST /chat/completions），「Custom API estimate — please confirm」橙条（ux-42）✅；「Test connection」成功文案「Connection successful — model service is reachable」友好（ux-39）
- **云端估算**：后端为 stub，实际走到的分支是错误态「Estimate unavailable — please enter values manually」（ux-16），文案可接受；云端成功徽标本环境不可得 ➖
- 两态徽标文案均一眼可辨且带「please confirm」人工确认引导，设计一致。

### 4. 复验旧项

- R1 隐私授权同意后直达登录页（ux-01→02）✅ 未回退。
- 暗色主题首页对比度/可读性良好（ux-52）✅。

---

## 二、全页面过检速览

| 页面 | 截图 | 结论 |
|---|---|---|
| 隐私授权 | ux-01 | 布局/文案正常，同意直达登录 |
| 登录 | ux-02 | 正常 |
| 引导问卷/推荐/启动 | ux-03/04/05 | 正常 |
| 首页断食 | ux-05/47、ux-52（暗色） | 计时环/按钮态正常；文案小问题见清单 |
| 记录（搜索/份量/吐司/饮水） | ux-12/13/14/21 | 正常；键盘与溢出问题见清单 |
| 自定义食物 + AI 估算 | ux-15/16/35/42/43 | 流程顺畅，保存后直接进入份量入账 sheet，体验好 |
| 数据页 | ux-17/18/22/48/50 | 数据展示正常；冷启动空读问题见清单 |
| 趋势与报告 | ux-27 | 趋势出点正常；标签截断/单复数旧问题仍在 |
| 社区 | ux-23/24/25 | 发帖/feed/相对时间正常 |
| 设置 | ux-28/31 | 语言/主题/断食方案入口正常，版本 1.2.1 (15) |
| AI 模型页 | ux-06~10/29/33/34/40 | 新板块信息架构清晰；细节问题见清单 |
| 英文复验 | 全程英文截图 | 无残留中文、无 i18n key 裸奔 |

## 三、UX 问题清单

### 🔴 阻塞

**B1. 冷启动后当日营养数据全部读空，直到下一次写入才恢复（复发，三次会话均现）**
- 证据链：ux-22（4:41 入账后 Stats 168 kcal 正常）→ 重启 App → ux-47 首页「Nothing logged」、ux-48 数据页空、ux-49 记录页底部汇总消失 → 再入账 50g → ux-50 恢复 282 kcal（旧数据其实未丢）。
- 与 v1.1.2 复验时记录的「时钟拨动后空读、写入后恢复（392=280+112）」同一模式。疑似：冷启动时 `currentUserIdProvider` 先为 anonymous（登录态异步恢复），drift 聚合流以 anonymous 查询返回空后未随登录态恢复重查。
- 影响：用户每次冷启动看到「今日无记录」的假空态，数据页/首页信号卡/记录页汇总全中招。
- 建议：读取侧在登录态恢复后 invalidate 重建数据流，或启动时等待 auth ready 再装配数据源；补「冷启动→直接看数据页」的集成测试。

### 🟡 体验

**Y1. 记录页键盘顶起时底部溢出 38px（BOTTOM OVERFLOWED）**
- ux-43：搜索无结果空态 + 「1 logged today」汇总行 + 键盘升起三者叠加时，渲染溢出 38px，debug 下黄黑警告条 + 文字重叠。release 无警告条但同样裁剪。
- 建议：空态区改为可滚动或键盘升起时收起汇总行/链接。

**Y2. AI 模型页自定义 API 表单未交互先亮红**
- ux-26/36/37：进入页面即显示「Custom provider requires a Base URL / a model name」红字（表单未触碰）。ux-29（中文进入同表单）又不显示——展示时机不一致。
- 建议：校验改为失焦/首次 Save 后触发。

**Y3. 端侧模型 Cancel 后 Resume 进度从 0% 重新爬升，续传未生效**
- ux-08（4%）→ Cancel（ux-09 显示 Paused 7%）→ Resume（ux-10 显示 0%）→ 50 秒后仅 5%（ux-11），速度与首下一致、未瞬时越过 7%，判定为从头重下。AGENTS.md 记载 Range 续传为既有特性，UI 表现不符。
- 建议：排查续传 offset 与进度回调基数；至少在 UI 上区分「续传中（已完成 x%）」。

**Y4. 下载进度条轨道为实心橙色，0% 时看似已满**
- ux-07/10：绿色进度 + 橙色满轨，0% 时整条橙色，第一眼误读为已完成。建议轨道改浅灰、进度保留品牌绿。

**Y5. 表单提交后键盘不自动收起**
- ux-21（Log it 后）、ux-43（Save 后）键盘仍停留在屏幕，遮挡 toast 与底部内容。建议提交动作后 `FocusScope.unfocus()`。

### 🔵 打磨

1. 生效链路卡分隔符为双 em-dash「——」（ux-06），中英文都显得突兀，建议改单破折号或冒号。
2. 「Prefer on-device estimates」开关关闭态为黑白线框样式，与设置页绿色填充开关不一致（ux-33 vs ux-28）；开启后一致。
3. 自定义 API 表单区无卡片标题（链路卡叫它 Custom API，表单区只有 Provider 下拉，ux-06），建议补「Custom API」小节标题与另两张卡对齐。
4. 搜索框无一键清空按钮（ux-44），长关键词只能逐字删。
5. 报告页 7-day journey 标签截断「Days logg…」「Fasting g…」「Weight ch…」仍未修（ux-27，v1.1.1 已报 Y3）；「1 entries logged」单复数（ux-27）。
6. 中文首页方案 chip 用「进食窗」、环下用「进食窗口中」，用词不统一（ux-30）。
7. AI 模型页 Provider 中译「供应商」，「服务商」更常见（ux-29）。
8. App 名称显示为小写「eatwise」且仍用 Flutter 默认图标（ux-46 应用抽屉），品牌打磨项。
9. 首页进食窗口态仍显示「This fast counts toward Sep 16」（ux-47），当前无进行中断食，文案沿用旧口径。

### 环境/非问题说明

- ux-45 出现的「Gemma4-E2B Spike」页面经查是 AVD 上**独立的 gemma_spike 应用**（应用抽屉可见），非 eatwise 内嵌页面，不计入 eatwise UX 问题；其批量推理日志（0.8-1.0s/次）与端侧估算实测一致。
- 云端估算徽标不可得系后端 LLM stub，非客户端缺陷。

## 四、总体 UX 评价

v1.2.1 的 AI 来源可见性设计（生效链路卡 + 徽标 + 「please confirm」引导）信息架构清晰、文案自然，是本版本亮点；端侧模型五态覆盖完整，下载在切页面/切语言场景下稳定。全 App 中英文案质量整体自然，暗黑模式可用性良好。主要欠缺：**冷启动数据空读（B1）**——它让「打开 App 看一眼今日数据」这一最高频场景在每次冷启动时给出错误答案，建议最高优先级修复；其次是下载续传（Y3）与进度条可读性（Y4）这组端侧下载体验细节。组件一致性（开关样式、卡片标题、轨道配色）再过一遍设计规范即可收口。
