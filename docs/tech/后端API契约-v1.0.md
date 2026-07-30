# 《明食 · EatWise — 后端 API 契约》v1.0

> 本文档定义客户端（Flutter 单代码库，iOS 15+ / Android 8.0+，D-14）与后端（Node.js NestJS + PostgreSQL + Redis，D-17）之间的 REST API 契约，是前后端并行开发、Mock、契约测试的唯一接口锚点。
> 决策依据：《开放问题决策记录 v1.0》（引用标注 D-xx）；数据模型依据：PRD v1.0 第五章。
> 状态标注：`〔假设〕` = 本文档补充的合理默认值，可开发、需团队确认；`〔待外部确认〕` = 需营养/法务/运营等外部角色书面确认。

---

## 文档信息

| 项 | 内容 |
|----|------|
| 文档名称 | 后端 API 契约 |
| 版本 | v1.0 |
| 撰写日期 | 2026-07-27 |
| 关联文档 | PRD v1.0、设计方案定稿、需求评审记录、《00-决策记录-开放问题拍板 v1.0》 |
| 适用端 | iOS 15+ / Android 8.0+（Flutter 3.x，D-14 / D-17） |
| 覆盖版本范围 | MVP（P0：认证/用户/断食方案/断食记录/饮食记录/食物库）+ V1.1（P1：营养/激励/社区）的接口前瞻定义 |

### 版本记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-07-27 | 首版契约，覆盖 PRD 第五章全部 8 个实体 |

---

## 一、通用约定

### 1.1 Base URL 与环境

| 环境 | Base URL〔假设，域名待定后替换〕 | 用途 |
|------|------------------------------|------|
| 开发 dev | `https://api-dev.eatwise.example.com/v1` | 日常开发，数据可随时重置 |
| 测试 staging | `https://api-staging.eatwise.example.com/v1` | 回归/契约测试，近似生产数据脱敏副本 |
| 生产 prod | `https://api.eatwise.example.com/v1` | 正式环境 |

- 所有路径以 `/v1` 为版本前缀；破坏性变更升 `/v2`，同版本内只做向后兼容变更（新增字段、新增可选参数）。
- 全站 HTTPS（TLS 1.2+），HTTP 一律 301 到 HTTPS。

### 1.2 认证：JWT access + refresh（D-13 / D-17）

| 项 | 约定 |
|----|------|
| 认证方式 | `Authorization: Bearer <accessToken>` |
| accessToken | JWT，有效期 2 小时〔假设〕，payload 含 `sub`(userId)、`iat`、`exp`、`jti` |
| refreshToken | 不透明随机串，有效期 30 天〔假设〕，滑动续期（每次刷新换新 refreshToken，旧值作废，Reuse Detection 触发全端登出） |
| 多端登录 | 允许，同一用户最多 5 个活跃设备会话〔假设〕，超出踢最旧 |
| 无感刷新 | 客户端在 accessToken 过期前 5 分钟或收到 `401 + AUTH_TOKEN_EXPIRED` 时调 `POST /auth/refresh` |
| 注销 | `POST /auth/logout` 使当前设备 refreshToken 失效并解绑推送 token |

公开接口（无需 accessToken）：`/auth/sms/send`、`/auth/login/*`、`/auth/refresh`、健康检查 `/health`。

### 1.3 通用请求/响应结构

**成功响应**（HTTP 2xx）：

```json
{
  "data": { },
  "meta": { "serverTime": "2026-07-27T12:00:00.000Z", "requestId": "req_01J..." }
}
```

**失败响应**（HTTP 4xx/5xx），错误结构三段式 `code / message / details`：

```json
{
  "error": {
    "code": "FOOD_ENTRY_CONFLICT",
    "message": "该记录在别处已被修改，请刷新后重试",
    "details": { "serverVersion": 7, "conflictFields": ["grams"] }
  },
  "meta": { "serverTime": "2026-07-27T12:00:00.000Z", "requestId": "req_01J..." }
}
```

| 字段 | 说明 |
|------|------|
| `error.code` | 稳定机器可读码（SCREAMING_SNAKE），客户端分支判断**只认 code**，不认 message |
| `error.message` | 按 `Accept-Language` 本地化的用户可读文案（zh-CN / en，D-15），可直接上屏 |
| `error.details` | 可选结构化补充（字段错误列表、冲突信息、重试秒数等） |
| `meta.serverTime` | 服务端 UTC 时间，供客户端校准时钟漂移（配合 D-07） |
| `meta.requestId` | 链路追踪 ID，客服/日志排查凭据 |

### 1.4 时间戳与时区（D-07）

- 所有时间戳 **UTC 存储、UTC 传输**，格式 ISO 8601 毫秒：`2026-07-27T12:00:00.000Z`。
- 「归属日」「当日」等自然日概念**不在 URL/体中用裸日期字符串推断**：客户端必须在请求头携带 `X-Timezone: Asia/Shanghai`（IANA 名称），服务端用它把 UTC 换算到本地自然日。查询类接口另支持显式 `date=2026-07-27`（本地自然日，配合 `X-Timezone` 解析为 UTC 区间）。
- 打卡归属日规则 = **进食窗口所属自然日**（一次断食归入其后的进食窗口那天），由服务端统一计算，客户端不自行判定（D-07）。
- 客户端每次请求可依赖 `meta.serverTime` 校准本机被回拨/快进的系统时间。

### 1.5 幂等约定：`clientRequestId`（D-20）

| 约定 | 内容 |
|------|------|
| 适用范围 | 所有非 GET 写接口 |
| 生成方 | 客户端，每条本地记录创建时生成 UUID v4，持久化在本地记录上 |
| 传递方式 | 请求体字段 `clientRequestId`（批量接口逐条携带）；幂等键 = `userId + clientRequestId` |
| 服务端行为 | 相同幂等键重复到达 → 返回**首次处理结果**（HTTP 200 + 相同 data），不重复落库、不重复计数 |
| 保留期 | 幂等记录保留 90 天〔假设〕 |

### 1.6 分页约定：游标分页

| 参数 | 说明 |
|------|------|
| `cursor` | 上一页响应返回的 `pageInfo.nextCursor`，首页不传 |
| `limit` | 每页条数，默认 20，最大 50〔假设〕 |

```json
"pageInfo": { "nextCursor": "eyJsYXN0SWQiOi...", "hasMore": true }
```

适用接口：断食历史、饮食记录历史、食物搜索、常吃列表、打卡流、点赞列表等所有列表。**不使用 offset 分页**（离线增量同步与实时插入场景下 offset 会错位）。

### 1.7 i18n 错误消息（D-15）

- 请求头 `Accept-Language: zh-CN` 或 `en`，缺省 `zh-CN`。
- 服务端所有 `error.message`、审核拒绝原因、补签卡状态文案等按该头返回对应语言；客户端设置内切换语言后同步更新该头。
- 业务数据（食物名、信号灯建议）本身双语存储，由响应同时下发或按语言下发，见各模块。

### 1.8 通用错误码总表

| HTTP | code | 说明 |
|------|------|------|
| 400 | `VALIDATION_ERROR` | 参数校验失败，`details.fields` 列字段级错误 |
| 400 | `INVALID_CURSOR` | 游标非法或过期 |
| 400 | `INVALID_SYNC_TOKEN` | syncToken 过期/非法，需全量重拉（见 4.6） |
| 401 | `AUTH_TOKEN_EXPIRED` | accessToken 过期，走刷新流程 |
| 401 | `AUTH_TOKEN_INVALID` | token 伪造/已吊销，强制重新登录 |
| 401 | `AUTH_REFRESH_REUSED` | refreshToken 重放，全部会话已登出（安全事件） |
| 403 | `ACCOUNT_DELETED` | 账号已注销/删除中 |
| 404 | `NOT_FOUND` | 资源不存在或不属于当前用户 |
| 409 | `CONFLICT` | 通用冲突（etag 不匹配、唯一约束），`details` 给服务端现状 |
| 409 | `IDEMPOTENCY_PAYLOAD_MISMATCH` | 同 clientRequestId 但请求体指纹不同（客户端 bug，不应重试） |
| 410 | `RESOURCE_GONE` | 资源已删除（如已删除的 Post 再点赞） |
| 429 | `RATE_LIMITED` | 触发限流，`details.retryAfterSec` 给重试秒数 |
| 500 | `INTERNAL_ERROR` | 服务端错误，客户端指数退避重试 |
| 503 | `MAINTENANCE` | 维护中〔假设需要〕 |

---

## 二、数据模型与服务端字段约定

在 PRD 第五章 8 个实体基础上，补充同步与决策记录要求的服务端字段。**所有实体含** `id`（UUID v4，服务端生成）、`createdAt`、`updatedAt`（UTC，服务端时钟，LWW 仲裁基准，D-20）、`deletedAt`（软删，null=未删）。

| 实体 | 服务端关键字段（PRD 基础上补充） | 说明与决策依据 |
|------|----------------------------------|----------------|
| User | `phone`(E.164，可空)、`wechatOpenId`(可空)、`appleSub`(可空)、`nickname`、`avatarUrl`、`gender`、`birthYear`、`heightCm`、`weightKg`、`activityLevel`(sedentary/light/moderate/high)、`goal`(fat_loss/health_metric/routine/trial)、`locale`(zh-CN/en)、`timezone`、`themePref`(light/dark/system)、`accessibilityPrefs`(json：大字号/减弱动效等)、`onboardingStatus`(none/skipped/completed)、`exportStatus`、`deletionStatus` | 登录方式 D-13；i18n D-15；隐私导出/删除 D-18 |
| FastingPlan | `planType`(14:10/16:8/18:6；5:2 仅展示不入库，D-03)、`eatingWindowStart`、`eatingWindowEnd`（本地时刻 `HH:mm`，配合 User.timezone 解释）、`effectiveDate`（生效本地日，**次日 0 点生效**，D-06）、`status`(current/pending/expired) | 同 userId 仅一条 current；更换产生一条 pending（次日生效） |
| FastingRecord | `attributionDate`（归属本地日 = 进食窗口所属自然日，服务端算，D-07）、`plannedStartAt/plannedEndAt`（UTC）、`actualStartAt/actualEndAt`（UTC，可空）、`extendedMinutes`（累计延长，≤240，D-10）、`fastedMinutes`（实际断食时长）、`result`(on_track/completed/ended_early/broken)、`isQualified`（达标布尔，D-08）、`eventLog`(jsonb 状态变更日志) | 达标判定在服务端：提前破窗 ≤15 分钟（配置热调）仍算达标（D-08） |
| FoodEntry | `clientRequestId`、`eatenAt`(UTC)、`foodId`、`grams`、`inputMethod`(photo/voice/frequent/manual)、`nutritionSnapshot`(jsonb：kcal/proteinG/carbsG/fatG 按份量换算后快照)、`version`(int，etag/LWW 版本号)、`syncStatus` 仅客户端本地四态（提交中/已同步/待同步/冲突），**服务端只存权威态**（D-20） | 撤销窗 10 秒为客户端行为（D-11），服务端不感知；快照防止食物库更新回溯改历史 |
| Food | `nameZh`、`nameEn`、`aliases`(string[] 中英混合)、`kcalPer100g`、`proteinPer100g`、`carbsPer100g`、`fatPer100g`、`category`、`source`(cn_fct/usda) | 双语库 ≥3000 条（D-16）；Food 为平台级共享数据，不含 userId |
| DailyNutrition | `date`（本地日）、`kcal/proteinG/carbsG/fatG`（累计）、`targets`(jsonb：当日目标快照，D-04)、`signals`(jsonb：四营养素各 {level: green/yellow/red, percent, adviceKey}，D-05) | 由 FoodEntry 服务端实时聚合；阈值/目标公式热配置（D-04/D-05 待外部背书） |
| Streak | `currentStreak`、`longestStreak`、`lastQualifiedDate`、`milestones`(jsonb：{3: achievedAt, 7: ..., 30: ...})、`makeupCards`(jsonb：{stock, month, usedDates[]}) | 口径 = 断食打卡达标（D-12）；补签卡：每月 1 日发 2 张、当月有效月底清零、库存上限 2、仅补最近 7 天断签日（D-12） |
| Post | `text`、`imageUrls`(string[])、`streakDaysAtPost`、`likeCount`、`auditStatus`(pending/approved/rejected)、`auditReason`（可空，双语）、`visibility`(self/followers/public 预留) | 先审后发（D-17）；pending 仅作者可见 |

---

## 三、模块接口

> 每张接口表列：方法/路径/说明/幂等与冲突策略。请求体、响应体字段以表格或 JSON 示例给出。未特别说明的响应均包在 `data` 内。

### 3.1 认证（D-13）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| A1 | POST | `/auth/sms/send` | 发送手机验证码 | 幂等键 = `phone + 场景`；同号 60s 内重发返回 429〔假设〕 |
| A2 | POST | `/auth/login/phone` | 手机号+验证码登录（无账号则注册） | 同验证码仅可用一次；连续错误 5 次锁 10 分钟〔假设〕 |
| A3 | POST | `/auth/login/wechat` | 微信登录（code 换 openid） | 同 code 一次性；已绑定账号直接登录，未绑定自动注册并绑定 |
| A4 | POST | `/auth/login/apple` | Apple 登录（identityToken） | **iOS 上架强制提供**（D-13）；Android 端不展示该入口 |
| A5 | POST | `/auth/refresh` | 刷新令牌 | refreshToken 滑动轮换；旧值重放 → `AUTH_REFRESH_REUSED` 全端登出 |
| A6 | POST | `/auth/logout` | 注销当前设备会话 | 幂等，重复调用返回 200 |
| A7 | POST | `/devices/push-token` | 上报推送 token | 幂等键 = `userId + deviceId`，重复上报更新即可（upsert） |

**A1 发送验证码**

请求：`{ "phone": "+8613800138000", "scene": "login" }`
响应：`{ "data": { "ttlSec": 300, "resendAfterSec": 60 } }`
错误码：`RATE_LIMITED`、`VALIDATION_ERROR`（号段非法）

**A2 手机登录**

请求：`{ "phone": "+8613800138000", "code": "123456", "device": { "deviceId": "d-uuid", "platform": "ios", "osVersion": "17.5", "appVersion": "1.0.0" } }`
响应（完整示例见 §5.1）：`accessToken / refreshToken / expiresIn / user / isNewUser`

**A7 推送 token 上报（双端差异）**

| 平台 | `provider` 值 | 说明 |
|------|---------------|------|
| iOS | `apns` | APNs device token（D-17） |
| Android（海外/Play） | `fcm` | FCM registration token |
| Android（国内厂商） | `getui` 或 `jpush` | 经聚合推送 SDK 的 cid/token〔待外部确认：M0 定个推或极光，D-17〕 |

请求：`{ "deviceId": "d-uuid", "provider": "apns", "token": "…", "locale": "zh-CN" }`

> 注：M2 窗口提醒使用**本地通知**（D-09），不依赖推送在线；远程推送仅用于社区互动、补签卡发放提醒等〔假设〕。

---

### 3.2 用户资料（M7 / D-18）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| U1 | GET | `/users/me` | 读取当前用户（含营养目标计算结果快照） | — |
| U2 | PATCH | `/users/me` | 修改资料（基础信息/目标/偏好） | 幂等（带 clientRequestId）；冲突 = 字段级 LWW，以服务端 `updatedAt` 为准；触发营养目标重算（D-04） |
| U3 | POST | `/users/me/export` | 申请数据导出（敏感个人信息权利，D-18） | 幂等；生成中重复申请返回当前任务状态 |
| U4 | GET | `/users/me/export/:taskId` | 查询导出任务/下载链接 | 链接有效期 24h〔假设〕 |
| U5 | POST | `/users/me/deletion` | 申请删除账号 | 幂等；7 天冷静期〔假设，待法务确认 D-18〕内可撤销 |
| U6 | DELETE | `/users/me/deletion` | 冷静期内撤销删除申请 | 幂等 |

**U1 响应要点**：`user` 对象 + `nutritionTargets`（kcal/proteinG/carbsG/fatG，由 D-04 公式按最新资料算出；缺基础信息时用兜底值并回 `targetsFallback: true`，引导补全资料）。

**U2 请求体（部分字段示例）**：

```json
{
  "clientRequestId": "uuid",
  "nickname": "林悦",
  "gender": "female",
  "birthYear": 1998,
  "heightCm": 165,
  "weightKg": 58,
  "activityLevel": "light",
  "goal": "fat_loss",
  "timezone": "Asia/Shanghai",
  "locale": "zh-CN",
  "themePref": "system",
  "accessibilityPrefs": { "largeText": false, "reduceMotion": false }
}
```

响应：更新后的完整 `user` + 重算后的 `nutritionTargets`。冲突处理：本接口字段级 LWW，无 409；客户端持旧快照整体覆盖的极端场景由 `version` 字段预留（当前不启用）〔假设〕。

**U5 删除语义**（D-18，〔待外部确认：法务确认留存与匿名化口径〕）：申请后账号进入 `deletionStatus=pending`，立即登出所有会话、停止处理个人数据；冷静期满后台物理删除/匿名化健康数据；Post 等 UGC 匿名化（头像昵称清除，内容留存与否待法务定）。

---

### 3.3 断食方案（M1 / D-03 / D-06）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| P1 | GET | `/fasting-plans/catalog` | 方案库目录（14:10/16:8/18:6 说明，双语，D-03；5:2 仅 `displayOnly` 标记） | — |
| P2 | POST | `/fasting-plans/recommendation` | 提交问卷答案，返回主推荐+备选+推荐理由（D-02/D-03） | 幂等（纯计算，不落库） |
| P3 | GET | `/fasting-plans/current` | 当前方案（含 pending 更换） | — |
| P4 | PUT | `/fasting-plans/current` | 一键启动/更换方案，**次日 0 点本地生效**（D-06） | 幂等（带 clientRequestId）；已有 pending 时整体替换该 pending（同义操作，LWW）；当日 current 不受影响 |
| P5 | PATCH | `/fasting-plans/current/window` | 调整进食窗口时间段（不更换 planType） | 幂等；同样次日生效（归入 D-06 语义）〔假设：窗口调整与换方案生效时机一致〕 |

**P2 请求**：`{ "q1Goal": "fat_loss", "q2Schedule": "regular", "q3Experience": "beginner" }`（均可空，空 = 跳过，走 16:8 兜底 D-03）
**响应**：`{ "primary": { "planType": "14:10", "window": {"start":"10:00","end":"20:00"}, "reasonKey": "reco.beginner" }, "alternatives": [ { "planType": "16:8", ... } ] }` — `reasonKey` 为 i18n key，文案客户端本地化（D-03 推荐理由模板化双语）。

**P4 请求**：

```json
{
  "clientRequestId": "uuid",
  "planType": "16:8",
  "eatingWindow": { "start": "12:00", "end": "20:00" }
}
```

**响应**：`{ "current": {...}, "pending": { "planType": "16:8", "effectiveDate": "2026-07-28", "status": "pending" } }` — 客户端按确认弹窗明示「明日 0:00 生效」（D-06）。服务端在 `effectiveDate` 当天 0 点（用户 timezone）将 pending 翻转为 current。

---

### 3.4 断食记录（M2 / D-07 / D-08 / D-10）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| F1 | GET | `/fasting/status` | 当前断食状态（首页计时环数据源） | — |
| F2 | POST | `/fasting/end` | 手动「结束断食」上报 | 幂等（clientRequestId）；重复结束返回首次结果；对已完成记录再结束返回 409 `FASTING_ALREADY_ENDED` |
| F3 | POST | `/fasting/extend` | 「延长」上报，步进 30 分钟、累计 ≤240 分钟（D-10） | 幂等；超限返回 400 `FASTING_EXTEND_LIMIT` |
| F4 | GET | `/fasting/records` | 历史记录，按归属日查询 | 游标分页；`?from=2026-07-01&to=2026-07-27`（本地日，配合 X-Timezone） |
| F5 | GET | `/fasting/records/:attributionDate` | 单日记录详情（含 eventLog） | — |

**F1 响应（完整示例见 §5.2）要点**：

| 字段 | 说明 |
|------|------|
| `state` | `fasting` / `eating`（当前应处窗口，服务端按方案+UTC 推算） |
| `window.eatingStartAt / eatingEndAt` | 当前周期进食窗口 UTC 边界 |
| `activeRecord` | 进行中的 FastingRecord（含 `attributionDate`——「本次断食计入 X 月 X 日」归属文案数据源，评审项 1） |
| `toleranceMinutes` | 达标容差（默认 15，服务端配置热调，D-08） |
| `extendRemainingMinutes` | 今日剩余可延长分钟数（240 − 已延长，D-10） |

**F2 请求**：`{ "clientRequestId": "uuid", "recordId": "uuid", "endedAt": "2026-07-27T03:52:00.000Z" }`
**响应**：更新后的 record，含 `result` 与 `isQualified`：

| 场景（D-08） | `result` | `isQualified` |
|--------------|----------|---------------|
| 进食窗口按时开启 | `completed` | true |
| 手动提前结束 ≤15 分钟（容差热调） | `ended_early` | true |
| 手动提前结束 >15 分钟 | `broken` | false |
| 延长后最终时长 ≥ 计划时长 | `completed` | true |

达标判定由**服务端**执行，`endedAt` 以服务端收到时间校验客户端上报值（漂移 >5 分钟采信服务端时间）〔假设〕，streak 联动 D-12。

**F3 请求**：`{ "clientRequestId": "uuid", "recordId": "uuid", "extendMinutes": 30 }`（仅允许 30 的倍数，累计 ≤240）
**响应**：更新后 record（`plannedEndAt` 后移、进食窗口相应后移不压缩，D-10）+ `extendRemainingMinutes`。

---

### 3.5 饮食记录（M3 / D-11 / D-16 / D-20）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| E1 | POST | `/food-entries` | 创建单条饮食记录 | 幂等（clientRequestId 去重，D-20） |
| E2 | PATCH | `/food-entries/:id` | 修改（份量/时间/食物） | 幂等 + etag：`If-Match: <version>`；版本不符 → 409 + 服务端现值（字段级 LWW 由客户端合并后重试，D-20） |
| E3 | DELETE | `/food-entries/:id` | 删除（软删） | 幂等，重复删除返回 200 |
| E4 | POST | `/food-entries/batch-upsert` | **批量上行同步**（离线积压批量提交） | 逐条幂等；逐条返回 success/conflict，见 §5.3 |
| E5 | GET | `/food-entries` | 按日期/区间查询当日明细 | `?date=` 本地日或 `from/to` |
| E6 | GET | `/sync/food-entries?syncToken=` | **增量下行**（多端/重装拉变更） | syncToken 失效 → 400 `INVALID_SYNC_TOKEN`，客户端全量重拉 |
| E7 | POST | `/food-entries/photo-recognition` | 拍照识别（异步任务，D-16 异步不阻塞） | 幂等（clientRequestId）；返回 taskId 轮询 |
| E8 | GET | `/food-entries/photo-recognition/:taskId` | 识别结果查询 | 任务 TTL 10 分钟〔假设〕 |

**E1 请求体**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `clientRequestId` | uuid | 幂等键（必填） |
| `eatenAt` | ISO8601 | 进食时间（默认现在） |
| `foodId` | uuid | 食物库条目 |
| `grams` | number | 份量（克），>0，≤5000〔假设上限〕 |
| `inputMethod` | enum | photo / voice / frequent / manual |
| `photoUrl` | string 可空 | 拍照入口的原图 |

**响应**：`entry`（含服务端计算的 `nutritionSnapshot` 与 `version: 1`）+ `dailyNutrition`（当日聚合后新值，客户端乐观更新校准用）。营养换算在**服务端**按食物库每 100g 值 × grams/100 计算并写快照，保证多端一致。

**E4 批量上行**（D-20 同步防腐层核心）：

请求：`{ "changes": [ { "op": "create|update|delete", "clientRequestId": "...", "entry": {...}, "baseVersion": 3 }, ... ] }`（单批 ≤100 条〔假设〕）
响应：逐条结果数组，每项 `{ clientRequestId, status: applied|conflict|error, serverEntry?, error? }`；冲突项返回服务端现值，由客户端按字段级 LWW（服务端 `updatedAt` 优先）合并进冲突队列并提示（D-20）。不可合并场景（一端已删除另一端修改）返回 `status: conflict, conflictType: deleted_vs_modified`，双份保留待用户处理（D-20）。

**E6 增量下行**：响应 `{ "changes": [ {entry 全量或 tombstone: {id, deletedAt}} ], "syncToken": "st_xxx", "hasMore": false }`。syncToken 有效期 30 天〔假设〕；tombstone 保留 90 天〔假设〕。

---

### 3.6 食物库（D-16）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| K1 | GET | `/foods/search?q=` | 双语搜索：`q` 同时匹配 `nameZh / nameEn / aliases` | 只读；游标分页 |
| K2 | POST | `/foods/batch-get` | 按 id 批量取（离线缓存校验/详情） | 幂等（只读语义），body `{ "ids": [...] }` ≤200 个〔假设〕 |
| K3 | GET | `/foods/frequent` | 常吃列表（按用户历史频次排序，M3 常吃复用） | 只读；`?limit=` 默认 20 |

**K1 搜索规则**：

| 规则 | 内容 |
|------|------|
| 匹配 | `q` 大小写不敏感，前缀 > 子串 > 别名 的优先级排序；中英文混合输入原样匹配（不翻译） |
| 高亮 | 响应含 `matchedOn`(nameZh/nameEn/alias) 与 `highlight` 区间，客户端高亮 |
| 空结果 | 返回空数组 + `suggestions`（相近词，≤3 条）〔假设〕 |
| 排序 | 相关度 × 用户个人使用频次加权 |

响应字段：`id / nameZh / nameEn / aliases / kcalPer100g / proteinPer100g / carbsPer100g / fatPer100g / category`。完整示例见 §5.4。

---

### 3.7 营养（M4 / D-04 / D-05）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| N1 | GET | `/nutrition/daily?date=` | 当日 DailyNutrition + 四营养素信号灯 | 只读；当日无记录返回 `hasData: false`（客户端空状态，PRD M4 边界） |
| N2 | GET | `/nutrition/trends?from=&to=&metrics=` | 趋势区间查询（热量/蛋白/碳水/脂肪/体重） | 只读；区间 ≤93 天〔假设〕 |
| N3 | POST | `/body-metrics` | 体重/饮水轻量记录（M3 附属） | 幂等（clientRequestId）；同 `date+type` upsert（LWW） |
| N4 | GET | `/body-metrics?from=&to=` | 体重/饮水历史 | 游标分页 |

**N1 响应要点**：

```json
{
  "date": "2026-07-27",
  "hasData": true,
  "totals": { "kcal": 1450, "proteinG": 62, "carbsG": 150, "fatG": 48 },
  "targets": { "kcal": 1600, "proteinG": 100, "carbsG": 180, "fatG": 53, "fallback": false },
  "signals": [
    { "nutrient": "protein", "level": "yellow", "percent": 62, "adviceKey": "advice.protein.low.dinner" },
    { "nutrient": "kcal",    "level": "green",  "percent": 91, "adviceKey": "advice.kcal.ok" }
  ]
}
```

- `level` 判定区间 = D-05 阈值表（以摄入÷目标百分比）；阈值与目标公式热配置，**上线前需营养侧书面背书**〔待外部确认，D-04/D-05〕。
- `adviceKey` 为规则模板库 i18n key（营养素 × 落区 × 餐段，中英双语，D-05）；文案客户端渲染，三重编码（颜色+图标+文字）由 UI 保证（PRD M8）。

---

### 3.8 激励：Streak 与补签卡（M5 / D-12）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| S1 | GET | `/streak` | 当前 streak、历史最长、里程碑、补签卡状态 | 只读 |
| S2 | POST | `/streak/makeup` | 使用补签卡补签 | 幂等（clientRequestId）；重复补同一日期返回 409 `MAKEUP_ALREADY_USED` |
| S3 | GET | `/streak/milestones` | 里程碑达成列表（3/7/30 天，含达成时间与分享图卡数据） | 只读 |

**S1 响应**：

```json
{
  "currentStreak": 6,
  "longestStreak": 21,
  "lastQualifiedDate": "2026-07-26",
  "recordDays": { "total": 34, "note": "仅展示不进 streak" },
  "makeupCards": {
    "stock": 1,
    "grantsThisMonth": 2,
    "expiresAt": "2026-07-31",
    "usableWindowDays": 7,
    "status": "available"
  }
}
```

**补签卡规则表（D-12，服务端强制执行）**：

| 规则 | 值 | 违规响应 |
|------|-----|----------|
| 发放 | 每月 1 日 2 张（按用户 timezone 的月） | — |
| 库存上限 | 2 张，不累积 | 发放时已有 2 张则不增发 |
| 有效期 | 当月有效，月底清零 | — |
| 可补范围 | 最近 7 个自然日内的断签日 | 超出 → 400 `MAKEUP_OUT_OF_WINDOW` |
| 无卡 | stock=0 | 400 `MAKEUP_CARD_EMPTY` |
| 中断主流程 | streak 归零（由断食不达标触发，服务端事务内完成）；断签弹窗所需三态由 S1 返回：`available` / `empty` / `broken`（最近断签且不可补） | — |

**S2 请求**：`{ "clientRequestId": "uuid", "date": "2026-07-25" }`（补签的归属日）
**响应**：更新后 Streak（`currentStreak` 重算连回）+ 该日生成一条 `result: makeup` 的 FastingRecord 标记〔假设：补签在断食历史中留痕〕。

**里程碑**：`currentStreak` 跨越 3/7/30 时服务端写入 `milestones` 并（经推送 token）发送成就提醒；客户端首页徽章与庆祝动效以 S1/S3 数据驱动（设计稿 §5.1）。

---

### 3.9 社区（M5 P1 / D-17）

| # | 方法 | 路径 | 说明 | 幂等/冲突 |
|---|------|------|------|-----------|
| C1 | POST | `/posts` | 发布打卡（图文） | 幂等（clientRequestId）；返回 `auditStatus: pending`（先审后发） |
| C2 | GET | `/posts/feed` | 打卡流（单列卡片） | 只读；游标分页；仅返回 `approved` 的他人帖子 + 本人的 pending/approved |
| C3 | GET | `/posts/:id` | 单帖详情（含审核状态） | 只读；pending/rejected 仅作者可见，他人 404 |
| C4 | DELETE | `/posts/:id` | 删除本人打卡 | 幂等 |
| C5 | POST | `/posts/:id/like` | 点赞 | 幂等键 = `postId + userId`，重复点赞返回 200 不重复计数 |
| C6 | DELETE | `/posts/:id/like` | 取消点赞 | 幂等 |
| C7 | POST | `/posts/:id/report` | 举报 | 幂等（同用户同帖一次）；进入人工审核队列 |

**C1 请求**：`{ "clientRequestId": "uuid", "text": "第 7 天！", "imageUrls": ["https://cdn.../a.jpg"], "linkedStreakDays": 7 }`
**C1 响应**：

```json
{
  "id": "p_uuid",
  "auditStatus": "pending",
  "text": "第 7 天！",
  "imageUrls": ["https://cdn.../a.jpg"],
  "streakDaysAtPost": 7,
  "likeCount": 0,
  "createdAt": "2026-07-27T12:00:00.000Z"
}
```

**审核状态机（先审后发，D-17）**：

| 状态 | 进入条件 | 可见性 | 迁移 |
|------|----------|--------|------|
| `pending` | 发布成功默认态 | 仅作者（打卡流中本人可见，带「审核中」标记） | 机审通过 → `approved`；机审异常/疑似 → 转人工队列后 → `approved`/`rejected` |
| `approved` | 审核通过 | 全量可见（MVP UGC 不分语言圈，D-15） | 举报成立 → `rejected`（下架） |
| `rejected` | 审核拒绝 | 仅作者可见 + `auditReason`（双语） | 作者删除即终态 |

- 审核服务：第三方内容安全 API（阿里云/腾讯云，〔待外部确认：M0 定，D-17〕）；机审目标耗时 ≤30s〔假设〕，超时按 `pending` 持续，不阻塞发布响应。
- 图片先经 `POST /uploads/images`（获取一次性上传凭证 → 直传 CDN → 回调校验）〔假设〕。

---

## 四、写接口幂等与冲突处理总表（D-20）

| 接口 | 幂等机制 | 冲突策略 | 冲突时响应 |
|------|----------|----------|------------|
| A1 发短信 | phone+scene 限频 | — | 429 |
| A5 刷新 | refreshToken 一次性轮换 | 重放 = 安全事件 | 401 `AUTH_REFRESH_REUSED` |
| A7 推送 token | upsert by deviceId | LWW | 200 |
| U2 改资料 | clientRequestId | 字段级 LWW（服务端 updatedAt 仲裁） | 200（合并后现值） |
| U3/U5 导出/删除申请 | 任务唯一 | 重复申请返回在途任务 | 200 |
| P4 换方案 | clientRequestId | pending 单例替换（LWW） | 200 |
| F2 结束断食 | clientRequestId + 状态机 | 已结束记录拒绝 | 409 `FASTING_ALREADY_ENDED` |
| F3 延长 | clientRequestId + 上限校验 | 累计超限拒绝 | 400 `FASTING_EXTEND_LIMIT` |
| E1 创建记录 | clientRequestId 去重 | 同键不同体 = 客户端 bug | 409 `IDEMPOTENCY_PAYLOAD_MISMATCH` |
| E2 修改记录 | clientRequestId + **etag(`If-Match: version`)** | 版本不符 → 字段级 LWW 由客户端合并重试 | 409 `CONFLICT` + 服务端现值 |
| E3 删除记录 | 软删幂等 | 已删除 → 200 | 200 |
| E4 批量上行 | 逐条 clientRequestId | 逐条 LWW；删除 vs 修改不可合并 → 双份保留人工提示 | 逐条 `applied/conflict/error` |
| N3 体重/饮水 | clientRequestId | 同 date+type upsert，LWW | 200 |
| S2 补签 | clientRequestId + 规则表 | 规则外拒绝（见 §3.8 表） | 400/409 |
| C1 发打卡 | clientRequestId | — | 200（pending） |
| C5 点赞 | postId+userId 唯一约束 | 重复点赞忽略 | 200 |

四态持久化（提交中/已同步/待同步/冲突）为**客户端本地状态**（SQLite drift，D-17/D-20）；服务端通过本表的幂等与冲突响应支撑状态翻转：上行成功 → 已同步；网络失败 → 待同步；收到 conflict → 冲突。「待同步 N 条」入口数据由客户端本地统计，无服务端接口。

---

## 五、关键接口 JSON 示例

### 5.1 登录（A2 手机号验证码登录）

请求：
`POST /v1/auth/login/phone`
```json
{
  "phone": "+8613800138000",
  "code": "483920",
  "device": { "deviceId": "9f1c2a-device-uuid", "platform": "ios", "osVersion": "17.5", "appVersion": "1.0.0" }
}
```

响应 `200`：
```json
{
  "data": {
    "accessToken": "eyJhbGciOiJFUzI1NiIs...",
    "refreshToken": "rt_4f8a2c...",
    "expiresIn": 7200,
    "isNewUser": false,
    "user": {
      "id": "u_01890abc",
      "nickname": "林悦",
      "locale": "zh-CN",
      "timezone": "Asia/Shanghai",
      "goal": "fat_loss",
      "onboardingStatus": "completed"
    }
  },
  "meta": { "serverTime": "2026-07-27T12:00:00.000Z", "requestId": "req_01J9X7" }
}
```

失败 `400`：
```json
{ "error": { "code": "AUTH_CODE_INVALID", "message": "验证码错误或已过期", "details": { "remainingAttempts": 3 } }, "meta": { "serverTime": "2026-07-27T12:00:01.000Z", "requestId": "req_01J9X8" } }
```

### 5.2 断食状态（F1）

`GET /v1/fasting/status`（头：`X-Timezone: Asia/Shanghai`）

响应 `200`：
```json
{
  "data": {
    "state": "fasting",
    "plan": { "planType": "16:8", "eatingWindow": { "start": "12:00", "end": "20:00" } },
    "window": { "eatingStartAt": "2026-07-27T04:00:00.000Z", "eatingEndAt": "2026-07-27T12:00:00.000Z" },
    "activeRecord": {
      "id": "fr_01J9",
      "attributionDate": "2026-07-27",
      "plannedStartAt": "2026-07-26T12:00:00.000Z",
      "plannedEndAt": "2026-07-27T04:00:00.000Z",
      "extendedMinutes": 30,
      "result": "on_track"
    },
    "toleranceMinutes": 15,
    "extendRemainingMinutes": 210,
    "streak": { "currentStreak": 6 }
  },
  "meta": { "serverTime": "2026-07-27T02:30:00.000Z", "requestId": "req_01J9Y1" }
}
```

客户端据此渲染：断食中，倒计时 = `eatingStartAt − serverTime`（用 serverTime 校准本地时钟漂移），归属文案「本次断食计入 7 月 27 日」（评审项 1）。

### 5.3 批量上行同步（E4）

`POST /v1/food-entries/batch-upsert`
```json
{
  "changes": [
    { "op": "create", "clientRequestId": "c-aaa-1",
      "entry": { "eatenAt": "2026-07-27T01:10:00.000Z", "foodId": "f_rice", "grams": 200, "inputMethod": "frequent" } },
    { "op": "update", "clientRequestId": "c-bbb-2", "baseVersion": 3,
      "entry": { "id": "fe_777", "grams": 150 } },
    { "op": "delete", "clientRequestId": "c-ccc-3", "entry": { "id": "fe_888" } }
  ]
}
```

响应 `200`（逐条结果，整体永不整体失败）：
```json
{
  "data": {
    "results": [
      { "clientRequestId": "c-aaa-1", "status": "applied",
        "serverEntry": { "id": "fe_901", "version": 1, "nutritionSnapshot": { "kcal": 232, "proteinG": 5.2, "carbsG": 51.8, "fatG": 0.6 } } },
      { "clientRequestId": "c-bbb-2", "status": "conflict", "conflictType": "version_mismatch",
        "serverEntry": { "id": "fe_777", "version": 4, "grams": 180, "updatedAt": "2026-07-27T01:20:00.000Z" } },
      { "clientRequestId": "c-ccc-3", "status": "applied" }
    ],
    "syncToken": "st_2026-07-27T01:30:00Z_x9",
    "dailyNutrition": { "date": "2026-07-27", "kcal": 1450 }
  },
  "meta": { "serverTime": "2026-07-27T01:30:00.000Z", "requestId": "req_01J9Z2" }
}
```

### 5.4 食物双语搜索（K1）

`GET /v1/foods/search?q=ji&limit=20`（头：`Accept-Language: zh-CN`）

响应 `200`：
```json
{
  "data": {
    "items": [
      {
        "id": "f_egg_001",
        "nameZh": "鸡蛋",
        "nameEn": "Egg",
        "aliases": ["ji dan", "鸡蛋(煮)", "boiled egg"],
        "kcalPer100g": 144, "proteinPer100g": 13.3, "carbsPer100g": 2.8, "fatPer100g": 8.8,
        "category": "蛋制品",
        "matchedOn": "alias",
        "highlight": { "field": "aliases", "text": "ji dan" }
      },
      {
        "id": "f_chicken_014",
        "nameZh": "鸡胸肉",
        "nameEn": "Chicken Breast",
        "aliases": ["ji xiong rou"],
        "kcalPer100g": 118, "proteinPer100g": 24.6, "carbsPer100g": 0.6, "fatPer100g": 1.9,
        "category": "畜禽肉",
        "matchedOn": "alias",
        "highlight": { "field": "aliases", "text": "ji xiong rou" }
      }
    ],
    "pageInfo": { "nextCursor": null, "hasMore": false }
  },
  "meta": { "serverTime": "2026-07-27T12:00:00.000Z", "requestId": "req_01JA01" }
}
```

---

## 六、限流与安全约定

### 6.1 限流（全部〔假设〕，上线前按压测校准）

| 维度 | 规则 | 触发响应 |
|------|------|----------|
| 全局 | 每 userId 300 req/min；每 IP（未登录）60 req/min | 429 + `details.retryAfterSec` |
| 发短信 A1 | 同手机号 1 次/60s、≤10 次/天；同 IP ≤20 次/天 | 429 |
| 登录尝试 A2–A4 | 同设备 10 次/分钟；验证码错 5 次锁 10 分钟 | 429 / 400 + 剩余次数 |
| 搜索 K1 | 每 userId 60 req/min | 429 |
| 拍照识别 E7 | 每 userId 30 次/天（第三方成本控制） | 429 |
| 发帖 C1 | 每 userId 20 帖/天 | 429 |
| 批量同步 E4 | 每 userId 30 批/小时 | 429 |

响应头统一携带 `X-RateLimit-Limit / X-RateLimit-Remaining / X-RateLimit-Reset`。

### 6.2 安全约定

| 项 | 约定 |
|----|------|
| 传输 | 全站 TLS 1.2+；生产环境 HSTS |
| Token 存储 | 客户端存 Keychain（iOS）/ Keystore 加密 SharedPreferences（Android）；禁止写日志 |
| 签名算法 | JWT ES256〔假设〕；密钥轮换经 kid |
| 防重放 | 幂等键 + refreshToken Reuse Detection（§1.2） |
| 验证码 | 6 位数字，5 分钟有效，一次性〔假设〕 |
| 敏感数据 | 健康数据为敏感个人信息：字段级访问最小化、导出/删除入口（U3–U6）、独立同意（首次启动隐私弹窗），法务 M0 介入〔待外部确认，D-18〕 |
| 日志脱敏 | 手机号/令牌/健康数值不落明文日志 |
| 上传 | 图片上传凭证一次性、限类型（jpg/png/webp）、限 10MB〔假设〕，服务端杀软/内容安全扫描 |
| 免责 | 营养/断食相关响应不含医疗建议；客户端全程展示「非医疗建议」声明（D-18） |

### 6.3 双端差异汇总

| 事项 | iOS | Android |
|------|-----|---------|
| 登录入口（D-13） | 手机号 + 微信 + **Apple（上架强制）** | 手机号 + 微信（无 Apple 入口） |
| 推送通道（D-17） | APNs | 海外 FCM；国内厂商通道经聚合 SDK〔待外部确认：个推/极光 M0 定〕 |
| 小组件 | WidgetKit + Live Activity（iOS 16.1+，低版本降级普通 Widget，D-14） | AppWidget（`home_widget` 桥） |
| 最低版本（D-14） | iOS 15 | Android 8.0（API 26） |
| 语音识别（D-16） | Speech framework | SpeechRecognizer |
| Token 存储 | Keychain | Keystore |

> API 层本身双端同构；差异仅体现在 A4 入口展示、A7 `provider` 取值与客户端实现。

---

## 七、遗留问题

| # | 事项 | 状态 | 负责人/节点 |
|---|------|------|-------------|
| 1 | TDEE 公式（D-04）与信号灯阈值（D-05）营养侧书面背书 | 〔待外部确认〕，规则已热配置，不阻塞开发 | 产品+营养专家，M4 上线 Gate |
| 2 | 隐私合规细节：账号删除冷静期时长、UGC 匿名化口径、数据留存期 | 〔待外部确认〕，法务 M0 介入 | 法务，D-18 |
| 3 | 国内 Android 聚合推送 SDK（个推/极光）与内容安全供应商（阿里云/腾讯云） | 〔待外部确认〕M0 定 | 技术，D-17 |
| 4 | 正式域名与各环境 Base URL | 〔假设〕占位 | 运维，M0 |
| 5 | 限流阈值、验证码长度/有效期、导出链接时效等标注〔假设〕的数值 | 压测与安全评审后校准 | 技术，灰度前 |
| 6 | FastingRecord 补签留痕（`result: makeup`）、窗口调整次日生效（P5）为本文档补充语义 | 〔假设〕，待产品与《规格-M2/M5》对齐确认 | 产品+技术 |


---

## 附录 B·实现新增端点（2026-07-30 补充，v1.1）

> 以下端点在初版契约之后实现，已在服务端上线（内存 DataStore + Prisma 通道）。

### B.1 应用版本（App 内更新检查）

| 端点 | 说明 |
|------|------|
| `GET /v1/app/version/latest?platform=android\|ios` | 返回 `{latestVersion, minSupportedVersion, releaseNotes{zh,en}, apkUrl, publishedAt, source}`。数据源：GitHub Releases（env `GITHUB_RELEASE_TOKEN`，私有仓库必需）→ 失败降级 env 静态配置（`APP_LATEST_VERSION`/`APP_APK_URL`）；按平台缓存 5 分钟；`minSupportedVersion` 取 `APP_MIN_SUPPORTED_VERSION`（默认 1.0.0，低于此版本客户端强制更新）。公开端点（@Public）。 |

### B.2 用户权利（合规落地）

| 端点 | 说明 |
|------|------|
| `POST /v1/users/me/export`（U3） | 同步聚合该用户 Profile/FoodEntry/FastingPlan/FastingRecord/Streak/Post 返回 JSON（排除 tombstone）。 |
| `POST /v1/users/me/deletion`（U5） | 申请删除账号：置 pending + 7 天冷静期（`scheduledDeletionAt`）并吊销全部 refresh token；幂等不后移。到期由调度器物理删除个人数据 + 打卡帖匿名化（posts.userId 置空，该字段已改可空）。 |
| `DELETE /v1/users/me/deletion`（U6） | 冷静期内撤销删除；冷静期内登录亦自动撤销（登录响应含 `deletionCancelled`）。 |

### B.3 同步协议扩展

- `/sync/push` 新增 `waterLog` 实体 op：`create`（幂等 clientRequestId）与 `delete`（tombstone）；无 update（饮水无编辑场景〔假设〕）。
- `/sync/pull` 随行返回 `waterLogChanges`。
- 已知缺口：Prisma schema 尚未包含 WaterLog 表，饮水同步仅内存驱动可用。

### B.4 社区与激励实现备注

- Posts：发布先审后发三态（approved 上流 / rejected 拒发双语 `POST_CONTENT_REJECTED` / pending 转人工不可见）；举报即下架；点赞幂等；已删帖操作返回 410 `RESOURCE_GONE`。
- `GET /posts/feed` 响应补 `author` 与 `likedByMe` 字段（初版契约未列）。
- 应用商店合规注意：删除冷静期与 Apple 5.1.1（账号删除即时性）的兼容性〔待法务确认〕。
