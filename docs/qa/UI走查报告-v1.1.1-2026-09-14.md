# UI 走查报告 — v1.1.1（Android，2026-09-14）

- **构建**：debug APK，`--dart-define=API_BASE_URL=http://10.0.2.2:3000/v1`，版本号 1.1.1 (12)
- **环境**：AVD `eatwise_test`（Android 36 arm64，1080×2400，系统语言 English）；后端 eatwise_server 内存模式（localhost:3000）
- **测试账号**：walktest02（App 内注册，走完整引导）；walktest03（API 创建，用于举报他人帖子）
- **截图目录**：`/tmp/ui_walkthrough/`（序号 + 页面名）
- **说明**：全程未改任何代码；发现的问题仅记录。系统语言为英文，故主走查在英文界面进行，中途切换简体中文验证 i18n 热切换后再切回英文复验。

---

## 1. 启动与登录

**截图**：01-login / 02-register / 03-register-weak-pwd / 04-privacy-policy / 05-terms / 06-register-filled-1

- 登录页、注册页布局正常，无溢出、无红屏。
- ✅ **密码强度 bug（本轮重点修复项）已修复**：注册页密码框输入 4 位 `abc1`，下方显示红字「Password must be at least 8 characters」，**无崩溃**；输满 8 位后变为三段强度条 +「Strength: weak」。
- ✅ **协议链接 bug（本轮重点修复项）已修复**：注册页勾选协议处的「Privacy Policy」「Terms of Service」均可正常打开 legal 正文页，不再被弹回登录页。
- 🔵 密码错误提示「Password must be at least 8 characters」显示在「Confirm password」输入框下方而非密码框下方，位置略易误读（见 03）。
- 🔵 各页面顶部状态栏时间/图标为白色，浅色背景下几乎不可见（见 01 等所有截图顶部）。

## 2. 首启隐私授权（计划外页面，发现阻塞 bug）

**截图**：08-fresh-login / 09-consent-checked / 10-after-consent / 11-after-consent-retry / 12-after-restart

- 全新安装首启进入「Welcome to EatWise」隐私授权页：主同意必勾 + 健康数据单独同意（默认不勾），布局与文案正常。
- 🔴 **「Agree and continue」点击后卡死**：两项勾选后按钮变绿可点，但点击后按钮变灰（`_submitting=true`）且**页面不发生任何跳转**，用户被永久困在授权页（二次点击无效，进协议页再返回仍无效）。根因（仅记录）：`privacy_consent_page.dart` 依赖「门禁翻转后 GoRouter redirect 自动放行」，但 `app_router.dart` 的 `refreshListenable` 只 merge 了 authGate/privacyGate 的 Listenable，`PrivacyConsentController.agree()` 直接改 `gate.agreed` 字段未必触发 router 刷新；且 `_submitting` 无复位路径。
- 兜底：强杀 App 重启后授权已落盘，可正常进入登录页（12-after-restart）。**新用户首次使用必现，需重启才能继续，属阻塞级**。

## 3. 注册引导（onboarding）

**截图**：14-onboarding-start / 15-onboarding-q2 / 16-onboarding-q3 / 17-onboarding-recommendation / 18-home-after-onboarding

- 注册（用户名 walktest02）后自动进入 3 题问卷（目标/作息/断食经验），进度条、Skip for now、Back/Continue 均正常。
- 方案推荐页：14:10 Gentle Start（Top pick）+ 16:8 备选 +「How does fasting work?」科普入口，布局正常。
- 「Start now」一键启动 → 首页，方案 14:10 生效、计时环运行。
- 🔵 与走查预期的差异：v1.1.1 引导**不含身高/体重/目标数值录入**（仅 3 道选择题），营养目标走 D-04 默认兜底，数据页有「complete your profile」提示。与代码注释一致，非 bug，但与 PRD 描述需对齐。

## 4. 首页（断食 Tab）

**截图**：18 / 19-endfast-confirm / 20-endfast-done / 52-home-plan-chip-tap / 57-en-home

- 计时环、方案 chip（14:10 · Eating window 10:00−20:00）、归属文案（This fast counts toward Sep 15）正常。
- ✅ 结束断食两步确认弹窗正常：「Fasted for 2 h 25 min / Planned 14 h / Ending more than 15 minutes early counts as not qualified」，Keep fasting / End fast 双按钮；确认后切换为 Eating window 倒计时态，End fast/Extend 正确置灰。
- ✅ 入账饮食后首页 mini 信号卡正常点亮（Protein/Carbs/Calories 三张 Warning 红卡）。
- 🟡 进食窗口状态下仍显示「This fast counts toward Sep 15」，当前并无进行中的断食，文案易误导（52/57）。
- 🔵 断食中环显示的是「剩余时间」但标签只有「Fasting」，首次看到 11:34 易误读为已断食时长（实际已断 2h25m，弹窗内才见真实时长）。

## 5. 记录 Tab

**截图**：21-log-tab / 22-log-search-en / 24-food-detail / 25-toast-autodismiss / 26-portion-required / 27-food-logged / 28-sync-pending-check / 29-weight-dialog / 30-weight-logged

- ✅ 英文搜索 `chicken` 正常出结果（鸡胸肉/鸡腿/鸡翅等）。中文搜索因模拟器无中文输入法且 ADB_INPUT_TEXT 广播不支持（无 ADBKeyBoard），**未能验证**，建议真机补测。
- ✅ 份量留空点「Log it」被拦：toast「Enter an amount greater than 0」。
- ✅ 填 150g 入账成功：toast「Logged / Undo」出现，底部汇总「1 logged today · ~168 kcal today (to be calibrated)」（112kcal/100g × 150g = 168，数值正确）。
- ✅ 撤销吐司约 4-6 秒后自动消失（25/28 对比），不 persist。
- ✅ 饮水 +300：卡片实时变为 300 / 2000 ml（+200/+300/+500 三档按钮）。
- ✅ 体重记录：弹窗输入 65.5 → 卡片显示 65.5 kg。
- ✅ 同步状态：入账后顶部出现「1 record(s) still on the way — will sync when online」横幅，约 20 秒内自动消失（同步成功；服务端 `/v1/nutrition/daily` 已能查到当日 168 kcal，见第 6 节佐证）。
- 🔵 键盘收起瞬间食物列表上移，点击坐标易错位（走查中误触 +300 饮水）——属列表重排，真实用户影响小，仅记录。

## 6. 数据 Tab（发现功能性 bug）

**截图**：31-stats-tab / 32-stats-recheck / 33-stats-nextday

- 🔴 **当日信号灯与近 7 日趋势恒为空**：当日已入账 1 条饮食（记录 Tab 底部与服务端 `/v1/nutrition/daily?localDate=2026-09-14` 均确认 `hasData:true, kcal:168`），但数据 Tab 始终显示「Nothing logged this day」「trends are warming up」，切 tab 重进无效。
  - 根因（仅记录）：写入侧 `recordRepositoryProvider`（record_providers.dart:37-45）构造 `RecordRepository` 时**未传 userId**，落 drift 用默认 `'anonymous'`；读取侧 `nutritionDataSourceProvider`（nutrition_data_controller.dart:114-123）按 `currentUserIdProvider`（登录后为真实 userId）查询 → 登录用户读写口径不一致，数据页永远查空。首页 mini 信号卡走写入侧同一仓储（anonymous 口径）所以正常。`WaterLogRepository` 同样缺 userId 参数，饮水趋势恐同病。
- ✅ 日期切换器：右箭头到「今天」后正确禁用（33）。
- ✅ 「Using default goals — complete your profile」D-04 兜底提示条正常显示。

## 7. 报告/趋势页（M6）

**截图**：35-report-page / 36-report-scroll

- 入口为数据页右上角 ✨ 图标（Trends & reports）。
- Growth trends（Weight/Calories/Fasting + 7D/30D 切换）空态正常（受第 6 节 bug 影响，有数据也只会显示空态）。
- This week（9/14 – 9/14）周报卡片锁定空态正常（仅 1 天数据）。
- 月报卡片（September 2026，M6 轻量版）正常：0 fasting days on target / 1 days logged / Avg. fast 2 h 26 m / Weight change —。
- 🟡 **同页数据自相矛盾**：7-day journey 显示「Days logged 0 d」，月报卡片却显示「1 days logged」（两处数据源口径不同，与第 6 节 userId 问题相关）。
- 🟡 7-day journey 四个指标的标签被截断：「Fasting g…」「Days logg…」「Weight ch…」（英文下宽度不足，36）。
- 🔵 月报「1 days logged」单复数语法。

## 8. 社区 Tab

**截图**：37-community-feed / 38-post-compose / 40-post-published / 41-post-liked / 43-feed-other-post / 44-report-dialog / 45-report-done

- ✅ 空态（Waiting for today's first check-in）正常；FAB + 进入发帖页。
- ✅ 纯文字发帖成功，feed 即时出现，默认昵称「EatWise buddy」、相对时间「Just now」。
- ✅ 点赞：心形变红、计数 0→1。
- ✅ 举报：他人帖子头部有旗标（自己的帖子无旗标，符合 post_card.dart `!post.isAuthor` 设计）→ 确认弹窗「Report this check-in? It will be taken down and sent for manual review.」→ 举报后 toast「Reported. Thanks for the heads-up.」且该帖从 feed 乐观移除。
- ✅ 下拉刷新可拉取到新帖（43）。
- 🔵 走查时 `input text` 输入的空格被写成字面 `%20`（测试方法问题，非 App bug）；发帖页 0/500 计数、streak 徽章提示条正常。

## 9. 我的/设置

**截图**：46-me-tab / 47-me-scroll / 48-ai-model / 49-ai-filled / 51-ai-test-toast / 54-language-dialog / 55-settings-zh

- Streak 卡片（0 days / 0 days / 2 Mend Cards left）、账号区（Phone number/Change password/My contributions/Sign out/Delete account）、隐私区（协议/导出数据/健康数据授权/数据分析授权开关）、偏好（语言/主题/AI 模型）、提醒、关于（Version 1.1.1 (12)）均正常。
- ✅ AI 模型配置页：Provider=Custom，Base URL/Model/API Key 可填，填齐后 Test connection 激活；假端点（http://10.0.2.2:9/fake）测试失败有 toast 反馈。
- 🟡 失败提示文案不友好：「Connection failed: connectionError」——`connectionError` 是 dio 内部错误类型名，直接拼给用户看，应映射为「无法连接服务器，请检查 Base URL」之类（51）。
- ✅ 语言热切换：System/简体中文/English 三档，切中文整页即时生效（55）。
- 🔵 用户名注册账号的「Phone number」行为空态无引导（可接受，仅记录）。
- 🔵 「账号同步状态」在设置页无常驻入口，仅在记录 Tab 有待同步横幅（见第 5 节）。

## 10. 英文复验

**截图**：56-en-settings / 57-en-home / 58-en-log / 59-en-community（另全程截图均为英文界面）

- ✅ 首页/记录/社区/设置切英文后无残留中文硬编码、无 `xxx.yyy` 形式 i18n key 裸奔。

## 11. 换方案验证（D-06 新闭环）— 不可达

**截图**：52-home-plan-chip-tap

- 🔴 **App 内找不到换方案入口，D-06「次日 0:00 生效」确认弹窗无法触发**：
  - 首页方案 chip（14:10 · Eating window）点击无任何响应（52）；
  - 设置页无方案相关条目（46/47 全页走查）；
  - 代码佐证（仅记录）：全工程唯一 `context.go('/onboarding')` 入口在首页**无方案**空态（fasting_home_page.dart:127）；而 `app_router.dart:70` 规定 `gate.completed && onOnboarding → '/'`，已完成引导的用户即使跳到 /onboarding 也会被弹回首页。D-06 弹窗逻辑本身存在于 recommendation_screen.dart:117-144，但已成事实上的死代码。
  - 「次日生效、当日方案不变」的实际行为因此**未能验证**。

---

## 问题清单汇总

### 🔴 阻塞（3）

| # | 问题 | 位置/证据 |
|---|------|-----------|
| R1 | 首启隐私授权页点「Agree and continue」后卡死，按钮置灰不再跳转，新用户必须强杀重启才能继续 | 09/10/11；privacy_consent_page.dart:31-44 + app_router.dart:48 |
| R2 | 数据 Tab 当日信号灯与 7 日趋势恒为空：饮食/饮水记录以 `anonymous` 写 drift、按真实 userId 读，登录用户读写口径不一致（首页信号卡正常、服务端数据正常，仅数据页空） | 31/32；record_providers.dart:37-45 vs nutrition_data_controller.dart:114-123 |
| R3 | D-06 换方案入口不可达：首页/设置均无入口，/onboarding 对已完成引导用户被路由弹回，「次日 0:00 生效」弹窗为死代码，功能未验证 | 46/47/52；app_router.dart:70 + fasting_home_page.dart:127 |

### 🟡 体验（4）

| # | 问题 | 位置/证据 |
|---|------|-----------|
| Y1 | AI 模型「测试连接」失败提示泄漏 dio 错误类型名：「Connection failed: connectionError」 | 51 |
| Y2 | 报告页 7-day journey 与月报卡片「已记录天数」自相矛盾（0 d vs 1 days logged），数据源口径不一 | 35/36 |
| Y3 | 报告页 7-day journey 指标标签英文截断（Fasting g… / Days logg… / Weight ch…） | 36 |
| Y4 | 进食窗口状态下首页仍显示「This fast counts toward Sep 15」，文案与状态不符 | 52/57 |

### 🔵 建议（7）

1. 状态栏时间/图标白色，浅色主题下全页面不可见（所有截图）。
2. 注册页密码强度红字提示显示在确认密码框下方而非密码框下方（03）。
3. 断食中计时环显示剩余时间但标签仅「Fasting」，易误读为已断时长（18）。
4. 月报「1 days logged」单复数（36）。
5. 设置页无账号同步状态常驻入口（仅记录 Tab 临时横幅）。
6. 用户名注册账号的 Phone number 空行无引导（46）。
7. onboarding 与 PRD 预期差异：无身高/体重录入（3 题问卷 + D-04 兜底），需与 PRD 对齐口径（14-17）。

### 未验证项（环境限制）

- 食物**中文搜索**：模拟器无中文输入法、ADB_INPUT_TEXT 广播不可用，建议真机补测。
- D-06 次日生效实际行为（入口不可达，见 R3）。
- Photo/Voice/Scan 三种录入方式（涉及相机/麦克风/扫码，本轮未覆盖）。

## 总体结论

v1.1.1 客户端主流程（注册 → 引导 → 断食 → 记录 → 社区 → 设置）页面渲染质量整体良好：无红屏、无布局错乱、无文字溢出，i18n 双语热切换干净，本轮两个重点修复项（密码强度提示崩溃、协议链接弹回）**均已确认修复**。但存在 3 个阻塞级问题：**首启授权卡死（R1）**、**数据页读写口径不一致导致统计恒空（R2）**、**D-06 换方案闭环入口缺失（R3）**，均建议进入主线修复后排期回归。R1 影响所有新用户首次启动，建议最高优先级。

---

## 附：v1.1.2 复验（2026-09-14 深夜，commit 938abc8 / bbf96fe）

环境同前（AVD eatwise_test，后端内存模式，账号 walktest02）。截图均为 `/tmp/ui_walkthrough/recheck-*.png`。三个 🔴 修复全部复验通过，另顺手复验了 🟡 Y1。

### R1 首启隐私授权卡死 → ✅ 已修复

`pm clear` 全新安装 → 授权页勾选两项 → 点「Agree and continue」→ **直接进入登录页**，不再卡死。
截图：recheck-r1-01-consent / recheck-r1-02-checked / recheck-r1-03-after-agree。

### R2 数据 Tab 统计恒空 → ✅ 已修复

登录 walktest02 → 记录页入账糙米 100g → 数据 Tab 当日四张信号灯卡正常显示（Calories 392 / Protein 9 / Carbs 82 / Fat 3，含目标值与建议文案），近 7 日热量趋势在 9/14 出现数据点。数值与服务端 `/v1/nutrition/daily` 一致（280 历史 + 112 新增 = 392，读写口径已对齐）。
截图：recheck-r2-03-log-tab / recheck-r2-05-food-logged / recheck-r2-06-stats / recheck-r2-07-stats-trend。

### R3 D-06 换方案不可达 → ✅ 已修复

设置 → Preferences 新增「Fasting plan」入口（副标题已预告次日生效）→ 推荐页选 14:10 → Start now → **弹出「Change fasting plan：The new plan takes effect at 00:00 on 2026-09-15. Today still follows your current plan.」** → 确认后回首页，当日方案 chip 仍为 16:8（不变）；将模拟器时钟拨到 9/15 后首页方案 chip 变为 14:10，**次日 0:00 生效闭环完整验证**。
截图：recheck-r3-01-settings / recheck-r3-02-plan-page / recheck-r3-03-plan-switched / recheck-r3-04-plan-change-dialog / recheck-r3-06-home-plan-unchanged / recheck-r3-07-home-nextday。

### 补测：数据页「断食」维度 7 日趋势 → ✅

拨时钟制造一条手动结束的断食记录（9/15 21:00 结束，1h）→ 9/16 查看数据 Tab → Fasting 维度 → 趋势图在 9/15 显示「1 h」数据点，weeklyFastingHours 接线正常。
截图：recheck-r4-04-endfast-dialog / recheck-r4-06-fasting-trend-916。

### 附带复验：Y1 AI 测试连接文案 → ✅ 已修复

假端点测试连接失败提示由「Connection failed: connectionError」改为「Connection failed: server unreachable — check the Base URL and your network」，不再泄漏 dio 类型名。
截图：recheck-y1-06-ai-toast。

### 复验中新发现（均不阻塞）

- 🔵 推荐页把备选方案升为 Top pick 后，卡片推荐理由文案未随方案切换：14:10 卡片显示「Let's start with the crowd favorite 16:8」（recheck-r3-03/04）。
- 🟡 时钟跨天大幅拨动后重启，数据页曾出现一次空态（9/14 显示 Nothing logged），但本地聚合数据实际未丢（随后新入账一笔后 9/14 显示 392=280+112，recheck-x-01），疑似登录态恢复/时钟变化后的读取时序问题；真实使用场景（跨午夜）建议观察或补集成测试。
- 🔵 强制杀进程跨越断食自然结束点（App 未在前台）时，该次断食未见到落记录的证据；手动结束路径已验证正常。若为设计如此（仅前台对账落记录）可忽略，建议确认跨午夜自动完成的断食是否有补录机制。

### v1.1.2 复验结论

三个 🔴（授权卡死/数据页口径/D-06 入口）与 Y1（AI 文案）全部修复并验证通过，断食维度趋势补测通过。模拟器时钟已拨回真实时间。剩余待办：中文搜索真机补测、上方 3 条新观察项排期。
