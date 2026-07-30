# 联调冒烟（M7 真实后端接入）

> 验证路径：发送验证码 → 登录拿 token → /sync/push 上行一条 FoodEntry → /sync/pull 拉回 → K1 搜索「米饭」。
> 已于 2026-07-28 实跑通过（内存 DataStore，7455 条食物库自动加载）。

## 1. 启动后端

```bash
cd eatwise_server
cp -n .env.example .env   # PORT=3000；未配 DATABASE_URL/REDIS_URL 走内存模式
npm run start:dev         # http://localhost:3000/v1
```

App 侧 dev 环境默认指向 `http://localhost:3000/v1`（可用
`--dart-define=API_BASE_URL=...` 覆盖；模拟器/Android 真机需改宿主机 IP）。
本地联调验证码固定 mock 为 **123456**。

## 2. curl 冒烟步骤

```bash
BASE=http://localhost:3000/v1

# A1 发送验证码 → {"ttlSec":300,"resendAfterSec":60}
curl -s -X POST $BASE/auth/sms/send -H 'Content-Type: application/json' \
  -d '{"phone":"+8613800138000","scene":"login"}'

# A2 登录（mock 验证码 123456）→ accessToken/refreshToken/expiresIn/user
LOGIN=$(curl -s -X POST $BASE/auth/login/phone -H 'Content-Type: application/json' \
  -d '{"phone":"+8613800138000","code":"123456"}')
TOKEN=$(echo "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["accessToken"])')

# K1 搜索「米饭」→ 取 foodId
FOODID=$(curl -s "$BASE/foods/search?q=%E7%B1%B3%E9%A5%AD&limit=1" \
  -H "Authorization: Bearer $TOKEN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["items"][0]["id"])')

# /sync/push 上行一条 FoodEntry（幂等 clientRequestId）→ 逐条 applied + serverEntry
curl -s -X POST $BASE/sync/push -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'X-Timezone: Asia/Shanghai' \
  -d "{\"ops\":[{\"clientRequestId\":\"11111111-2222-4333-8444-555555555555\",\"entity\":\"foodEntry\",\"op\":\"create\",\"payload\":{\"eatenAt\":\"2026-07-28T02:00:00.000Z\",\"foodId\":\"$FOODID\",\"grams\":200,\"inputMethod\":\"manual\"}}]}"

# /sync/pull 增量下行（首次不传 syncToken 全量）→ changes 含刚上行的记录
curl -s "$BASE/sync/pull" -H "Authorization: Bearer $TOKEN"

# A5 刷新（滑动轮换，旧 refreshToken 重放 → 401 AUTH_REFRESH_REUSED 全端登出）
curl -s -X POST $BASE/auth/refresh -H 'Content-Type: application/json' \
  -d '{"refreshToken":"<refreshToken>"}'
```

## 2.1 waterLog 饮水同步（两态 pending/synced，PRD M3 功能点 4）

已于 2026-07-30 实跑通过：create 幂等（同键重放返回首次 serverEntry）、
delete tombstone、/sync/pull 随行 `waterLogChanges` 下行、U3 导出包含 waterLogs。

```bash
# waterLog create（幂等 clientRequestId，重放同键同体返回首次结果）
curl -s -X POST $BASE/sync/push -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"ops":[{"clientRequestId":"aaaaaaaa-2222-4333-8444-555555555555","entity":"waterLog","op":"create","payload":{"amountMl":300,"loggedAt":"2026-07-30T01:00:00.000Z","localDate":"2026-07-30"}}]}'
# → results[0].status=applied，serverEntry.id 为服务端主键（客户端回填 serverId）

# /sync/pull → waterLogChanges 含该行（entity=waterLog 全量视图）
curl -s "$BASE/sync/pull" -H "Authorization: Bearer $TOKEN"

# waterLog delete（tombstone 上行：serverId + payload.clientRequestId 兜底定位）
curl -s -X POST $BASE/sync/push -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"ops":[{"clientRequestId":"bbbbbbbb-2222-4333-8444-555555555555","entity":"waterLog","op":"delete","serverId":"<serverEntry.id>","payload":{"clientRequestId":"aaaaaaaa-2222-4333-8444-555555555555"}}]}'
# → applied（幂等）；再次 /sync/pull → waterLogChanges 返回 {tombstone:{entity:"waterLog",id,deletedAt}}
```

## 2.2 导出 / 删除账号（合规 §4.2/§4.3，U3/U5/U6）

```bash
# U1 当前用户（手机号脱敏返回）
curl -s $BASE/users/me -H "Authorization: Bearer $TOKEN"
# → user.phone = "139****9000"，user.deletionStatus / scheduledDeletionAt

# U3 数据导出（聚合 JSON 直返，含 profile/foodEntries/fasting*/streak/posts/waterLogs）
curl -s -X POST $BASE/users/me/export -H "Authorization: Bearer $TOKEN"

# U5 申请删除（7 天冷静期〔假设〕；吊销全部 refresh token；幂等）
curl -s -X POST $BASE/users/me/deletion -H "Authorization: Bearer $TOKEN"
# → {"deletionStatus":"pending","scheduledDeletionAt":"...","coolingOffDays":7}

# 冷静期内重新登录 → 自动撤销，登录响应 deletionCancelled=true
# U6 主动撤销（幂等）
curl -s -X DELETE $BASE/users/me/deletion -H "Authorization: Bearer $TOKEN"
# → {"deletionStatus":null,"scheduledDeletionAt":null,"coolingOffDays":7}
```

## 3. 实跑结果（2026-07-28）

| 步骤 | 结果 |
|------|------|
| A1 发送验证码 | 200 `{"ttlSec":300,"resendAfterSec":60}` |
| A2 登录 | 200，签发 access/refresh，`isNewUser:true` |
| /sync/push 上行 | 200，`status:applied`，服务端快照 kcal=232（米饭 200g），返回 `syncToken` |
| /sync/pull 下行 | 200，`changes` 含该条，`hasMore:false` |
| K1 搜索「米饭」 | 200，命中 `f_41f0db7a 米饭 Rice (Cooked)`（`matchedOn:nameZh`） |
| A5 刷新 + 旧值重放 | 新令牌签发；旧值重放 → 401 `AUTH_REFRESH_REUSED`（Reuse Detection 符合契约 §1.2） |

## 4. App 侧接入点

- 网络层：`lib/core/network/`（dio 工厂、认证拦截器 401 refresh 重放、信封解包、
  Accept-Language 跟随 slang、X-Timezone 跟随设备时区）。
- 认证：`lib/features/auth/`（登录页 /login，AuthGate 路由门禁，令牌存
  flutter_secure_storage）。
- 同步：`RemoteRecordSync`（/sync/push ≤100/批上行、/sync/pull syncToken 增量下行
  入 drift，含 waterLogChanges 饮水下行），`RemoteWaterLogSync`（饮水两态
  pending/synced 上行：create 幂等 + delete tombstone），
  `RecordSyncEngine.syncNow()` 在启动 / 登录成功 / 饮水入账与撤销后触发。
- 设置页：U3 导出（服务端聚合 JSON 存文档目录）、U5/U6 删除申请/撤销
  （冷静期弹窗 + 冷静期内状态行）、U1 脱敏手机号、登录 deletionCancelled 提示。
- 食物搜索：本地 drift 优先 + 远端 K1 补充（远端结果合入本地缓存，离线降级纯本地）。
