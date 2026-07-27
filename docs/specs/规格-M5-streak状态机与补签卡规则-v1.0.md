# 《规格-M5 streak 状态机与补签卡规则》v1.0

> 本文档落地决策记录 D-12，是 M5「连续打卡（streak）与补签卡」的唯一实现与验收依据。
> 关联文档：PRD v1.0（M2/M5/M8）、《开放问题决策记录》v1.0（D-01/D-06/D-07/D-08/D-12/D-14/D-15/D-20）、《规格-M2 断食计时状态机》（达标判定来源）、《规格-数据同步与四态持久化》（同步四态）。
> 撰写日期：2026-07-27。状态：已定稿，可直接开发。

---

## 一、streak 唯一口径（D-12）

| 项 | 规则 | 依据 |
|----|------|------|
| streak 计数口径 | **仅以「断食打卡达标」累计**，即当日 FastingRecord 按 D-08 判定为达标（完整走完断食窗口；或手动提前结束 ≤15 分钟；或延长后实际断食时长 ≥ 计划时长；破窗容差 15 分钟为服务端热配置） | D-12、D-08 |
| 打卡归属日 | 一次断食归入**其后进食窗口所属自然日**，streak 按该归属日累计 | D-07 |
| 饮食记录天数 | **独立统计「记录天数」**（当日有 ≥1 条 FoodEntry 即 +1），仅作展示（如「我的」页数据卡），**不进 streak、不影响断签判定、不触发里程碑** | D-12 |
| 北极星关联 | 「有效记录日」（断食达标 **或** ≥1 条饮食记录）用于 WAU-Active 统计口径，与 streak 无耦合 | D-01 |
| 中断处理 | 断签 → 当前 streak 归零，进入「断签待处理」；7 天窗口内可用补签卡恢复（见第三、四章） | D-12 |
| 无方案用户 | 未启动断食方案的用户不产生 streak（状态=无连胜），不弹断签弹窗 | 〔假设〕 |
| 更换方案 | 更换断食方案（D-06 次日生效）**不清零 streak**，生效前后按各自方案窗口判定达标 | 〔假设〕 |

---

## 二、streak 状态机

### 2.1 状态定义

| 状态 | 枚举值 | 含义 | UI 表现 |
|------|--------|------|---------|
| 无连胜 | `NO_STREAK` | 当前连续天数 = 0，且无可补签的断签日（新用户、或断签已最终确认） | 首页不显示连胜标识，显示引导文案「完成今天断食，开启第 1 天」 |
| 连胜中 | `IN_STREAK` | 当前连续天数 ≥ 1，最近一个归属日已达标（或当日进行中断食尚未结算） | 首页/打卡卡展示「连续 N 天 🔥」 |
| 断签待处理 | `PENDING_MEND` | 前一日（或更早、仍在 7 天窗口内）未达标，streak 已归零，但断签日仍可补签 | streak 显示 0；下次启动弹「断签弹窗」（第五章）；社区/打卡流展示补签入口 |
| 已断签 | `BROKEN` | 断签日已超出 7 天补签窗口（或用户明示放弃），不可再补 | 与无连胜 UI 一致；断签弹窗中补签卡呈「已断签」态后不再重复弹出 |

> 说明：`PENDING_MEND` 与 `BROKEN` 下 `currentStreak` 均为 0，区别在于最近断签日是否仍在可补窗口内。

### 2.2 事件定义

| 事件 | 枚举值 | 触发源 |
|------|--------|--------|
| 当日达标 | `DAY_ACHIEVED` | M2 计时流按 D-08 判定某归属日达标（进食窗口按时开启 / 容差内提前结束 / 延长达标） |
| 当日未达标 | `DAY_MISSED` | 破窗 >15 分钟（D-08），或跨天结算时前一日无任何达标记录 |
| 使用补签卡 | `USE_MEND_CARD` | 用户在断签弹窗或打卡页对某个窗口内断签日使用补签卡 |
| 跨天结算 | `MIDNIGHT_SETTLEMENT` | 本地 0 点（用户本地时区）对前一日做结算；App 未启动时由服务端兜底结算（见 2.4） |

### 2.3 状态迁移表

| # | 当前状态 | 事件 | 条件 | 下一状态 | 副作用 |
|---|----------|------|------|----------|--------|
| T1 | NO_STREAK | DAY_ACHIEVED | — | IN_STREAK | currentStreak=1；lastAchievedDate=归属日；检查里程碑 3/7/30 |
| T2 | IN_STREAK | DAY_ACHIEVED | 归属日 = lastAchievedDate+1 | IN_STREAK | currentStreak+1；刷新 longestStreak；检查里程碑 |
| T3 | IN_STREAK | MIDNIGHT_SETTLEMENT | 前一日未达标 | PENDING_MEND | currentStreak=0；记录 lastMissedDate=前一日；置「待弹断签弹窗」标记 |
| T4 | NO_STREAK | MIDNIGHT_SETTLEMENT | 前一日未达标且用户已有过 streak 历史 | PENDING_MEND | 同 T3（currentStreak 保持 0） |
| T5 | NO_STREAK | MIDNIGHT_SETTLEMENT | 前一日未达标且用户从未有 streak（未启动方案） | NO_STREAK | 无（不弹窗）〔假设〕 |
| T6 | PENDING_MEND | USE_MEND_CARD | 库存 ≥1 且断签日距结算日 ≤7 天 | IN_STREAK | 断签日记为「已补签」；库存 −1；**streak 恢复为连续（含补签日）**：重算 currentStreak = 断签前 streak + 其后已连续达标天数（见 2.5 重算规则）；重检里程碑；刷新 longestStreak |
| T7 | PENDING_MEND | MIDNIGHT_SETTLEMENT | 最近断签日距今日 >7 天（窗口关闭） | BROKEN | 清除补签入口；断签弹窗不再弹出 |
| T8 | PENDING_MEND | DAY_ACHIEVED | 新一天达标（尚未补旧签） | IN_STREAK | currentStreak 从新达标日起算 = 1；旧断签日仍可补，补签成功后按 2.5 重算合并为连续 |
| T9 | BROKEN | DAY_ACHIEVED | — | IN_STREAK | currentStreak=1，开启新一段连胜 |
| T10 | 任意 | DAY_MISSED | 当日进行中破窗 >15 分钟 | 不变 | 仅记录 FastingRecord 不达标；真正归零发生在次日 0 点结算（T3/T4） |

> 幂等要求：同一归属日的 `DAY_ACHIEVED` 重复到达不得重复 +1（以 `userId + 归属日` 唯一约束去重，配合 D-20 的 `clientRequestId`）。

### 2.4 每日结算时机（双端）

| 场景 | 机制 | 说明 |
|------|------|------|
| 本地 0 点结算（主） | Flutter 端监听应用生命周期 + 定时器：App 处于前台跨过本地 0 点时，立即对前一日执行 `MIDNIGHT_SETTLEMENT`；iOS 用 `AppLifecycleState` + `Timer`，Android 相同（单代码库逻辑一致） | 结算在用户**本地时区** 0 点触发；时间戳 UTC 存储、本地渲染（D-07） |
| 后台结算（辅，尽力而为） | iOS：`BGTaskScheduler`（BGAppRefreshTask）；Android：`WorkManager` 每日周期任务 | 系统不保证精确 0 点执行，仅作体验增强，**不作为正确性依赖** |
| 服务端兜底结算（正确性保证） | 服务端定时任务按用户最近上报的时区，在其本地 0 点后（〔假设〕0 点后 30 分钟内）对未结算用户批量执行结算 | App 多日未启动时 streak 状态仍正确；客户端下次启动拉取服务端结算结果为准 |
| 冲突原则 | 以**服务端结算结果为权威**；本地先算先展示（乐观），拉取到服务端结果后覆盖（对齐 D-20 LWW） | 本地与服务端归属日判定逻辑必须共用同一份规则实现/同一参数（容差 15 分钟为服务端配置） |
| 时区变更 | 用户跨时区时，归属日按**断食发生时段用户本地时区**判定（沿用《规格-M2 断食计时状态机》结论）；streak 结算按用户当前本地时区 0 点 | 〔待外部确认〕与 M2 规格中对「跨时区当日归属」的最终拍板保持一致 |
| 回拨系统时间 | 结算依赖服务端时间校验：本地 0 点结算结果需与服务端对账，发现本地时钟异常（偏差 >5 分钟）时以服务端为准并标记 `syncState=冲突` | 对齐 D-20 冲突队列 |

### 2.5 补签后 streak 重算规则

设断签前一日 streak = S，断签日为 D，断签日后、补签操作前已有 k 个连续达标日：

- 补签 D 成功 → D 记为「已补签」（视同达标日），`currentStreak = S + 1 + k`（补签日计入，D-12「恢复为连续（含补签日）」）。
- 若 D 之后还存在其他未补签的断签日 D2（gap 未闭合），则仅当 gap 内**所有**断签日均被补签后才恢复连续；否则 currentStreak 从 D 之后第一个有效达标日起算。
- 因每月最多 2 张卡，gap 内断签日 >2 天时无法完全补回， streak 不可恢复为原值，仅能从最近连续段重算。
- 已补签日**计入** streak 天数与里程碑进度〔假设〕，分享图卡不标注补签来源〔假设〕。

---

## 三、补签卡规则表（D-12）

### 3.1 发放与库存

| 规则项 | 规则 | 备注 |
|--------|------|------|
| 发放时间 | 每月 1 日 00:00（用户本地时区）发放 2 张 | 服务端定时任务发放，发放入库留痕（见第六章发放记录） |
| 发放数量 | 每月 2 张 | 固定值，服务端配置可热调〔假设〕 |
| 库存计算 | 每月 1 日**重置为 2 张**（等价于：月底清零 + 月初发 2，不累积） | 上月剩余作废，不存在「攒卡」 |
| 库存上限 | 2 张 | 任何途径不得突破上限 |
| 每月使用上限 | 2 张/自然月 | 与库存一致；即便月中通过活动赠卡（V1.1+ 候选）也受此上限约束〔假设〕 |
| 新用户 | 注册当日即发放当月 2 张（当月剩余天数不足整月也发 2 张） | 〔假设〕 |
| 有效期 | 当月有效，月底 24:00（本地）清零 | 清零动作由月初重置覆盖实现，无需单独清零任务 |
| 使用范围 | 仅可补**最近 7 天内**的断签日：断签日 D 的可补窗口为 [D, D+6] 共 7 个自然日（含 D 当天），第 8 天起不可补 | 窗口按用户本地自然日计算 |
| 使用对象 | 仅可补「断食打卡未达标」的断签日；无方案日、未启动方案前的日期不可补 | — |
| 使用次数 | 同一断签日只能补 1 次；补签不可撤销 | 〔假设〕不可撤销 |

### 3.2 补签卡三态判定逻辑

断签弹窗与补签入口中，补签卡固定呈现三态之一（评审硬性要求）：

| 状态 | 判定条件（按序求值，命中即止） | UI 表现 |
|------|------------------------------|---------|
| 可补签 `MENDABLE` | 存在距今日 ≤7 天的未补签断签日 **且** 当月库存 ≥1 | 主按钮「使用补签卡恢复连胜」（轻盈绿填充），展示「本月剩余 N 张」 |
| 已用尽 `EXHAUSTED` | 存在距今日 ≤7 天的未补签断签日 **且** 当月库存 = 0 | 按钮置灰「本月补签卡已用完」，副文案「下月 1 日将发放 2 张新卡」 |
| 已断签 `UNMENDABLE` | 最近断签日距今日 >7 天（无可补断签日） | 不展示补签按钮，仅展示「连胜如何计算」说明 + 「补签窗口已关闭」 |

伪代码：

```
if exists(missedDay where today - missedDay <= 7 and not mended):
    return balance >= 1 ? MENDABLE : EXHAUSTED
else:
    return UNMENDABLE
```

---

## 四、断签弹窗规范（评审硬性要求）

### 4.1 触发与频控

| 项 | 规则 |
|----|------|
| 触发时机 | 跨天结算判定前一日未达标（T3/T4）后，用户**下次打开 App 进入前台**时弹出 |
| 频控 | 每个断签日只自动弹出 1 次；用户关闭后可在打卡页/「我的-连胜」再次进入补签流程；`BROKEN` 后不再自动弹出 |
| 必备内容（缺一不可，评审硬性） | ① 「连胜如何计算」说明；② 补签卡本月剩余次数；③ 补签卡三态（可补签/已用尽/已断签）之一的明确呈现 |
| 无障碍 | 三重编码（图标+文字+色彩，非单靠颜色）；按钮 ≥44px；支持 200% 字号；完整语义标签（M8 硬性） |

### 4.2 中英双语文案示例（i18n key 管理，D-15）

| 元素 | i18n key | 中文 | English |
|------|----------|------|---------|
| 标题 | `streak.break.title` | 哎呀，连胜中断了 | Your streak was interrupted |
| 连胜如何计算说明 | `streak.break.howItWorks` | 连胜只按「断食打卡达标」累计：每天按计划完成断食窗口（提前不超过 15 分钟也算达标）即连胜 +1；饮食记录天数单独统计，不影响连胜。中断后连胜归零，7 天内可用补签卡恢复。 | Your streak counts only days you complete your fasting plan (ending up to 15 min early still counts). Meal-log days are tracked separately and don't affect your streak. A missed day resets it to 0 — use a Mend Card within 7 days to restore it. |
| 剩余次数 | `streak.break.cardsLeft` | 本月剩余补签卡：{n} 张 | Mend Cards left this month: {n} |
| 可补签主按钮 | `streak.break.mendCta` | 使用补签卡，恢复 {days} 天连胜 | Use a Mend Card to restore your {days}-day streak |
| 已用尽 | `streak.break.exhausted` | 本月补签卡已用完，下月 1 日将发放 2 张新卡 | No Mend Cards left this month. You'll get 2 new ones on the 1st. |
| 已断签 | `streak.break.unmendable` | 断签已超过 7 天，补签窗口已关闭。从今天开始新的连胜吧！ | This miss is over 7 days old and can no longer be mended. Start a fresh streak today! |
| 次按钮 | `streak.break.dismiss` | 知道了，重新开始 | Got it, start fresh |

---

## 五、里程碑徽章与庆祝动效（3/7/30 天）

### 5.1 触发规则

| 规则项 | 规则 |
|--------|------|
| 里程碑档位 | 连续 3 天 / 7 天 / 30 天（PRD M5 固定三档） |
| 触发时点 | 跨天结算或当日达标事件使 `currentStreak` 首次达到档位值时触发（含补签日，见 2.5） |
| 解锁策略 | 每档**永久解锁一次**（徽章墙点亮，`milestones` 字段记录）；后续新一段连胜再次达到同档：播放轻量庆祝但不重复解锁徽章、不重复上报 `milestone_achieved`〔假设〕 |
| 展示 | 问候区滑入徽章（设计稿 §5.1-3：圆环外侧星点描边 + 「N 天连胜 🔥」），可点按生成分享图卡；徽章同时出现在社区打卡卡 |
| 文案示例 | 「连续 7 天！你已经超过了 80% 的伙伴 🎉」/「7-day streak! You've outlasted 80% of the community 🎉」（百分比为静态文案，〔待外部确认〕是否接真实分位数据） |

### 5.2 庆祝动效与降级（prefers-reduced-motion，M8 硬性）

| 场景 | 默认动效 | 降级动效（减弱动效开启时） |
|------|----------|---------------------------|
| 里程碑达成 | 圆环外侧星点描边浮现 + 徽章滑入 + 绿/橙光点迸发（克制，≤1.5s） | 取消粒子/滑入位移动画，改为**静态徽章淡入**（opacity 200ms 内，可进一步降为无动画直出） |
| 断食完成「破壳」 | 设计稿 §5.1-1 | 光点淡入静态徽章（设计稿既定降级方案） |

双端检测方式（Flutter 单代码库）：

| 平台 | 系统开关 | Flutter 读取 |
|------|----------|--------------|
| iOS 15+（D-14） | 设置 → 辅助功能 → 动态效果 → 减弱动态效果（`UIAccessibilityIsReduceMotionEnabled`） | `MediaQuery.of(context).disableAnimations` |
| Android 8.0+（D-14） | 设置 → 无障碍 → 移除动画（`animator_duration_scale = 0`） | 同上（Flutter 已桥接） |
| App 内 | 「我的 → 无障碍开关」提供 App 级「减弱动效」开关，开启时与系统开关取「或」 | 全局 MotionProvider 注入 |

---

## 六、数据模型

### 6.1 Streak 实体（每用户一条）

| 字段 | 类型 | 说明 |
|------|------|------|
| `userId` | String (PK) | 用户 ID |
| `currentStreak` | Int | 当前连续天数（断签/未补时 = 0） |
| `longestStreak` | Int | 历史最长连续天数 |
| `status` | Enum | `NO_STREAK / IN_STREAK / PENDING_MEND / BROKEN`（第二章） |
| `lastAchievedDate` | Date? | 最近一个有效达标日（含已补签日），本地自然日 |
| `lastMissedDate` | Date? | 最近断签日（用于 7 天窗口与三态判定） |
| `pendingMendDates` | List\<Date\> | 7 天窗口内全部未补签断签日（支持多日 gap） |
| `milestones` | JSON | `{ "3": achievedAt?, "7": achievedAt?, "30": achievedAt? }`，null=未解锁 |
| `mendCardBalance` | Int | 当月补签卡库存（0–2） |
| `mendCardMonth` | String | 当前库存所属月份 `yyyy-MM`，用于月初重置判定 |
| `mendCardUsedThisMonth` | Int | 本月已用张数（≤2） |
| `timezone` | String | 用户最近上报时区（IANA，如 `Asia/Shanghai`），供服务端兜底结算 |
| `syncState` | Enum | `提交中 / 已同步 / 待同步 / 冲突`（D-20 四态） |
| `updatedAt` | DateTime (UTC) | 服务端时间戳，LWW 依据 |

### 6.2 补签卡发放/使用记录（MendCardLedger，追加写）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String (PK) | 记录 ID |
| `userId` | String | 用户 ID |
| `type` | Enum | `GRANT`（发放）/ `USE`（使用）/ `EXPIRE`（月底清零留痕） |
| `month` | String | 所属月份 `yyyy-MM` |
| `count` | Int | 张数（GRANT=2；USE=1；EXPIRE=清零张数） |
| `mendedDate` | Date? | type=USE 时补签的断签日 |
| `createdAt` | DateTime (UTC) | 发生时间 |

### 6.3 StreakDay（每日明细，供日历/趋势展示与重算审计）

| 字段 | 类型 | 说明 |
|------|------|------|
| `userId + date` | 复合 PK | 归属日（D-07：进食窗口所属自然日） |
| `dayStatus` | Enum | `ACHIEVED`（达标）/ `MISSED`（未达标）/ `MENDED`（已补签）/ `NO_PLAN`（无方案） |
| `fastingRecordId` | String? | 关联 FastingRecord（D-08 判定来源） |
| `mendLedgerId` | String? | dayStatus=MENDED 时关联 6.2 记录 |

---

## 七、埋点事件

| 事件名 | 触发时机 | 关键参数 |
|--------|----------|----------|
| `streak_day_settled` | 跨天结算完成（本地或服务端） | `date`, `result`(achieved/missed), `currentStreak`, `settledBy`(client/server) |
| `streak_break_popup_shown` | 断签弹窗展示 | `missedDate`, `mendCardState`(mendable/exhausted/unmendable), `cardsLeft`, `lostStreakDays` |
| `streak_break_popup_action` | 弹窗内点击 | `action`(mend/dismiss), `mendCardState` |
| `mend_card_used` | 补签卡使用成功 | `mendedDate`, `restoredStreak`, `cardsLeft`, `usedThisMonth` |
| `mend_card_granted` | 月初/注册发放 | `month`, `count` |
| `mend_cards_expired` | 月底清零留痕同步 | `month`, `expiredCount` |
| `milestone_achieved` | 3/7/30 首次解锁 | `milestone`, `currentStreak`, `reducedMotion`(bool) |
| `milestone_shared` | 里程碑图卡分享 | `milestone`, `channel` |
| `streak_view` | 首页连胜标识曝光 | `currentStreak`, `status` |
| `record_days_view` | 「记录天数」独立统计曝光（与 streak 区分验证用） | `recordDays` |

---

## 八、测试要点列表（供 QA 用例引用）

**口径与状态机**
1. 当日达标（完整窗口 / 提前 ≤15 分钟 / 延长后达标）三种路径均触发 T1/T2 且 streak +1；提前 >15 分钟破窗当日不 +1、次日 0 点结算后归零（T10→T3）。
2. 饮食记录天数变化不影响 streak：只记饮食不断食，streak 不涨也不断（当日无方案判定外）；只断食不记饮食，streak 正常累计。
3. 同一归属日重复上报达标事件不重复 +1（幂等，`clientRequestId` 去重）。
4. 无方案用户不进入状态机、不弹断签弹窗（T5）；更换方案（次日生效）不清零 streak。

**结算时机与边界**
5. 前台跨本地 0 点：前一日未达标立即结算归零并置弹窗标记；前一日达标 streak +1。
6. App 连续 3 日未启动：服务端兜底结算，再次启动拉取后状态/归零/补签窗口均正确。
7. 跨时区（如上海→纽约）：归属日与结算 0 点按规则 2.4 判定，不多算/漏算一天。
8. 回拨系统时间 >5 分钟：以服务端结果为准，记录进入冲突队列（D-20）。
9. 夏令时切换日（美区时区）：结算不多触发、不漏触发〔待外部确认：MVP 上架区域是否覆盖夏令时时区〕。

**补签卡**
10. 月初重置：4 月剩 2 张未用 → 5 月 1 日库存 = 2（非 4）；当月用 1 张 → 次月 1 日库存 = 2。
11. 7 天窗口边界：断签日 D 在 D+6 可补，D+7 起不可补，状态 PENDING_MEND → BROKEN（T7）。
12. 库存 0 时存在可补断签日 → 三态 = 已用尽，按钮置灰；库存 ≥1 → 可补签；窗口外 → 已断签。
13. 补签成功：断签日记 MENDED，streak 按 2.5 恢复（含补签日、含其后续达标日 k），最长连胜刷新，补签不可撤销、同日不可重复补。
14. 多日 gap：gap 内 2 个断签日用 2 张卡全补 → 恢复连续；3 个断签日只能补 2 个 → 不恢复为原 streak，按最近连续段重算。
15. 新用户注册当日发放 2 张；每月使用 ≤2 张上限不可突破。

**断签弹窗（评审硬性验收）**
16. 弹窗同时包含：「连胜如何计算」说明 + 剩余次数 + 三态之一，中英双语各走查一遍（i18n key 无硬编码）。
17. 每个断签日仅自动弹 1 次；关闭后补签入口仍可达；BROKEN 后不再自动弹。

**里程碑与动效**
18. streak 首次达 3/7/30：徽章解锁 + 庆祝 + `milestone_achieved` 上报各一次；断签后重新达到同档不重复解锁。
19. 补签跨越里程碑（如 2 天 + 补 1 天 = 3 天）：里程碑正常触发。
20. 开启系统「减弱动效」（iOS/Android 各验一次）与 App 内开关：粒子/位移动画消失，静态徽章淡入；关闭后恢复默认动效。
21. 双端回归：以上全部用例在 iOS 15 最低支持设备与 Android 8.0（API 26）最低支持设备各跑一遍（D-14）。

---

## 附：遗留标注汇总

- 〔假设〕无方案用户不进 streak、不弹断签弹窗（2.1/T5）。
- 〔假设〕更换方案不清零 streak（第一章）。
- 〔假设〕已补签日计入 streak 与里程碑、分享图卡不标注补签来源；补签不可撤销（2.5/3.1/5.1）。
- 〔假设〕新用户注册当日发放当月 2 张；发放数量走服务端热配置（3.1）。
- 〔假设〕同一里程碑在新一段连胜中再次达到仅轻量庆祝、不重复解锁（5.1）。
- 〔待外部确认〕跨时区归属与 M2 规格最终拍板对齐（2.4）。
- 〔待外部确认〕里程碑「超过 80% 伙伴」是否接真实分位数据（5.1）。
- 〔待外部确认〕MVP 上架区域是否覆盖夏令时时区（第八章 #9）。
