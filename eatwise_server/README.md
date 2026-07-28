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
├── user/                    # U1/U2：资料读写 + 营养目标重算（D-04）
├── fasting/                 # P3/P4/F1/F2/F3：方案次日生效（D-06）、归属日（D-07）、
│                            # 容差达标（D-08）、延长步进/上限（D-10）
├── food/                    # K1/K2：双语食物搜索（D-16）
├── nutrition/               # N1：当日聚合 + 红黄绿信号灯（D-04/D-05 纯函数）
├── streak/                  # S1/S2/S3：streak 口径与补签卡（D-12）
└── sync/                    # E1/E4/E6：批量上行 ≤100/批、幂等去重、逐条 LWW 冲突、
                             # syncToken 增量下行（D-20 / 规格-数据同步）
prisma/schema.prisma         # 8 实体 + 幂等表（clientRequestId 唯一约束、version/updatedAt、软删）
test/                        # jest 单测 + supertest e2e
```

## 启动

```bash
npm install
cp .env.example .env        # 按需修改；不配 DATABASE_URL/REDIS_URL 则以内存数据层运行
docker compose up -d        # 可选：本地起 PostgreSQL + Redis
npx prisma migrate dev      # 可选：建表（需要 DATABASE_URL）
npm run start:dev           # http://localhost:3000/v1
```

## 常用脚本

| 命令 | 说明 |
|------|------|
| `npm run build` | nest build → dist/ |
| `npm run start:dev` | watch 模式启动 |
| `npm test` | jest 单测（51 个用例） |
| `npm run test:e2e` | supertest e2e（10 个用例） |
| `npm run lint` | eslint（零告警门禁） |
| `npm run prisma:generate` / `prisma:migrate` | Prisma client / 迁移 |

## 当前实现说明

- **数据层**：业务 Service 读写内存 `DataStore`（接口行为按契约实现，重启丢数据）；Prisma schema 已就位，接真实库时替换仓储层即可，Service 对外契约不变。〔假设〕
- **短信验证码**：mock 固定 `123456`，不落 Redis、不接短信通道。〔假设〕
- **JWT**：HS256 + 单密钥（`JWT_SECRET`）；契约建议 ES256 + kid 轮换，上线前替换。〔假设〕
- **限流**：@nestjs/throttler 全局 300 req/min 占位；分接口阈值（短信/登录/搜索等）按压测校准。〔假设〕
- **F2 endedAt**：直接采信客户端上报值；契约「漂移 >5min 采信服务端时间」待实现（TODO）。
- **同步**：批量上行覆盖 FoodEntry（create/update/delete、逐条 applied/conflict/error、deleted_vs_modified 双份保留）；fastingRecord/userProfile/fastingPlan 后续接入。
