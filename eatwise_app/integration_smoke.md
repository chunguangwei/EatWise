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
  入 drift），`RecordSyncEngine.syncNow()` 在启动与登录成功后触发。
- 食物搜索：本地 drift 优先 + 远端 K1 补充（远端结果合入本地缓存，离线降级纯本地）。
