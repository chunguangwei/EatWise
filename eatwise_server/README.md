# 明食 · EatWise — 后端服务（eatwise_server）

NestJS + TypeScript + PostgreSQL（Prisma）+ Redis（ioredis）。接口契约锚点：`docs/tech/后端API契约-v1.0.md`；决策锚点：`docs/00-决策记录-开放问题拍板-v1.0.md`。

## 目录结构

```
src/
├── main.ts                  # helmet、/v1 前缀、全局 ValidationPipe（防腐层 DTO 校验）
├── app.module.ts            # ConfigModule、Throttler 限流、全局过滤器/拦截器
├── common/                  # 错误码三段式过滤器、响应封装拦截器、i18n 字典（zh/en）、
│                            # 时区/UTC 工具（D-07）、内存数据层 DataStore
├── infra/                   # PrismaService、RedisService（懒连接）
├── auth/                    # A1/A2/A5/A6：验证码登录（D-13）、JWT 签发/刷新/轮换
├── user/                    # U1/U2：资料读写 + 营养目标重算（D-04）；U3 导出 / U5 删除 /
│                            # U6 撤销（合规 §4.2/§4.3，DeletionScheduler 到期扫描）
├── fasting/                 # P3/P4/F1/F2/F3：方案次日生效（D-06）、归属日（D-07）、
│                            # 容差达标（D-08）、延长步进/上限（D-10）
├── food/                    # K1/K2：双语食物搜索（D-16）、自定义食物（个人库）、估算端点
├── llm/                     # LLM 营养估算：Provider 可插拔（stub/deepseek/qwen/kimi/custom）、
│                            # 30 天结果缓存〔假设〕、每用户 10 次/分钟限流〔假设〕
├── nutrition/               # N1：当日聚合 + 红黄绿信号灯（D-04/D-05 纯函数）
├── streak/                  # S1/S2/S3：streak 口径与补签卡（D-12）
└── sync/                    # E1/E4/E6：批量上行 ≤100/批、幂等去重、逐条 LWW 冲突、
                             # syncToken 增量下行（D-20 / 规格-数据同步）
prisma/schema.prisma         # 8 实体 + 幂等表（clientRequestId 唯一约束、version/updatedAt、软删）
prisma/migrations/           # PostgreSQL 迁移（migrate diff 生成，migrate deploy 应用）
test/                        # jest 单测 + supertest e2e
```

## 启动

```bash
npm install
cp .env.example .env        # 按需修改；STORE_DRIVER=memory（默认）时无需数据库
npm run start:dev           # http://localhost:3000/v1
```

### 使用真实 PostgreSQL（STORE_DRIVER=prisma）

```bash
docker compose up -d postgres     # 起 PostgreSQL 16（redis 可选）
cp .env.example .env              # 配置 DATABASE_URL，并把 STORE_DRIVER 改为 prisma
npx prisma migrate deploy         # 应用 prisma/migrations/ 建表（开发期也可用 migrate dev）
npm run prisma:seed               # D-16：foods.seed.json 7455 条 upsert 入库（幂等可重跑）
npm run start:dev
```

- `STORE_DRIVER`：`memory`（默认，内存 DataStore，重启丢数据）/ `prisma`（PrismaStore + PostgreSQL，要求 `DATABASE_URL` 已配置且已 migrate，缺失时启动即报错）。
- 仓储抽象：`src/common/store/store-driver.ts` 定义 `StoreDriver` 接口（导出聚合 / 删除清除 / 食物种子 / 到期扫描），`MemoryStoreDriver` 适配内存 DataStore，`PrismaStore`（`src/common/store/prisma-store.ts`）走真实库——批量上行单 `$transaction` 原子提交、`(userId, clientRequestId)` 唯一约束幂等查重、LWW 乐观并发（`updateMany where version`）。
- 阶段性迁移说明：fasting/streak/social/sync 等业务 Service 当前仍直接读写同步内存 DataStore（接口契约不变）；prisma 模式已覆盖 U3 导出、U5 删除清除、食物库种子与批量上行四条持久化路径，其余模块的仓储迁移为后续工作。
- PrismaStore 集成测试（需真实库）：`RUN_PG_TESTS=1 DATABASE_URL=... npm test`（未起库时自动 skip）。

## LLM 营养估算（/v1/foods/estimate）

供应商可插拔，key 仅服务端配置，估算结果只作「估算」标记值（不写入权威食物库）。

| 环境变量 | 说明 |
|----------|------|
| `LLM_PROVIDER` | `stub`（默认，端点返回 503 `ESTIMATE_UNAVAILABLE`，客户端降级手动填写）/ `deepseek` / `qwen` / `kimi` / `custom`（任意 OpenAI 兼容端点） |
| `LLM_API_KEY` | 供应商 key；custom 本地 Ollama 可留空 |
| `LLM_BASE_URL` | custom 必填（内置供应商有默认值〔假设〕）。本地 Ollama：`http://localhost:11434/v1` |
| `LLM_MODEL` | custom 必填（内置供应商有默认值〔假设〕）。本地 Ollama 示例：`qwen3:4b` |

- 调用 `{base}/chat/completions`，system prompt 约束只返回 JSON，temperature 0.2，超时 15s；失败/超时/非法 JSON/营养越界（kcal 0-900、宏量 0-100）一律 `ESTIMATE_UNAVAILABLE`。
- 成功结果按「provider+model+规范化菜名」缓存 30 天〔假设〕，命中返回 `cached:true`；端点限流每用户 10 次/分钟〔假设〕。
- 用户自定义食物：`POST /v1/foods/custom`（幂等 clientRequestId，营养区间同上）入个人库，K1 搜索合并（仅创建者可见、排内置结果之后、标注 `isCustom`）；Prisma 对应 `foods.isCustom` + `createdByUserId`。

## 常用脚本

| 命令 | 说明 |
|------|------|
| `npm run build` | nest build → dist/ |
| `npm run start:dev` | watch 模式启动 |
| `npm test` | jest 单测（114 个用例 + 4 个 pg 集成用例 skip） |
| `npm run test:e2e` | supertest e2e（26 个用例） |
| `npm run lint` | eslint（零告警门禁） |
| `npm run prisma:generate` / `prisma:migrate` / `prisma:seed` | Prisma client / 迁移 / 食物库种子 |

## 当前实现说明

- **数据层**：默认内存 `DataStore` + `MemoryStoreDriver`；`STORE_DRIVER=prisma` 切换 `PrismaStore`（PostgreSQL 真实持久化），见上节。
- **用户权利（D-18 / 合规 §4）**：U3 `POST /users/me/export` 聚合全量个人数据 JSON 直返（本人数据含明文手机号）；U5 `POST /users/me/deletion` 进入 7 天冷静期〔假设〕（`deletionStatus=pending` + `scheduledDeletionAt`，立即吊销全部会话，幂等）；U6 `DELETE /users/me/deletion` 撤销；冷静期内重新登录视为撤销（响应 `deletionCancelled: true`）；`DeletionScheduler` 每 60s（`DELETION_SCAN_INTERVAL_MS` 可调）扫描到期账号执行物理删除 + 打卡帖匿名化。U1 响应手机号脱敏（`138****8000`）。U4 异步导出任务未实现（U3 同步直返替代）。
- **短信验证码**：mock 固定 `123456`，不落 Redis、不接短信通道。〔假设〕
- **JWT**：HS256 + 单密钥（`JWT_SECRET`）；契约建议 ES256 + kid 轮换，上线前替换。〔假设〕
- **限流**：@nestjs/throttler 全局 300 req/min 占位；分接口阈值（短信/登录/搜索等）按压测校准。〔假设〕
- **F2 endedAt**：直接采信客户端上报值；契约「漂移 >5min 采信服务端时间」待实现（TODO）。
- **同步**：批量上行覆盖 FoodEntry（create/update/delete、逐条 applied/conflict/error、deleted_vs_modified 双份保留）；fastingRecord/userProfile/fastingPlan 后续接入。
