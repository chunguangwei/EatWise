# AGENTS.md — 开发协作速查

> 给后续开发者与 AI 代理的实操指南。决策一律以 `docs/00-决策记录-开放问题拍板-v1.0.md`（D-01~D-20）为锚点；本文只讲「怎么跑起来、哪些坑不能踩」。

## 环境

- **Flutter SDK 内置**：`.tooling/flutter/bin`（3.44.8 / Dart 3.12.2），不要依赖系统 Flutter。所有命令先 `export PATH="$PWD/.tooling/flutter/bin:$PATH"`。
- **Android**：需 JDK 17+。系统 Java 版本不够时用 Android Studio 自带 JBR：
  `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`。
- **国内网络**：Android 依赖下载慢/卡死时 `export USE_CN_MIRRORS=1`（阿里云镜像）。CI（海外 runner）严禁开启。
- **iOS 真机**：Xcode → Settings → Accounts 需登录 Apple ID；项目签名团队 `L35RLT89XN`；部署目标 iOS 15.0。

## 客户端（eatwise_app/）

```bash
flutter pub get
dart run slang                  # i18n 生成（唯一正确方式）
dart run build_runner build     # drift 生成
dart analyze                    # 门禁：零 issue（含 info）
flutter test                    # 门禁：全绿
```

硬性规则：

- **禁止 `flutter analyze`**：中文路径下 SDK bug 会崩，用 `dart analyze`。
- **不要装回 `slang_build_runner`**：它不读 `slang.yaml`，会让 build_runner 整体失败。i18n 只有 `i18n/strings_zh-CN.i18n.json` / `strings_en.i18n.json` 两个文件（namespaces:false，多文件互相覆盖）。
- **代码一致性**：提交前 `dart format .` + `dart analyze` 零 issue + `flutter test` 全绿。CI 有 Android/iOS 双端构建门禁，本地改原生配置后至少跑 `flutter build apk --debug`。
- **分层**：feature-first（presentation/application/domain/infrastructure），Token 走 `lib/core/theme/` ThemeExtension，文案一律 i18n key 禁止硬编码。
- **领域逻辑纯函数化**：计时/营养/streak 等纯 Dart 可测，UI 只做接线。
- **端侧小模型 AI 估算（2026-09-15 核心层入库）**：`lib/core/llm/ondevice/`——Gemma4-E2B `.litertlm`（2.41GB，按需下载）。依赖 `flutter_gemma` + `flutter_gemma_litertlm` 必须成对（core 无引擎）；安装必须显式 `ModelFileType.litertlm`；`maxTokens` 是上下文窗口、限输出用 createChat `maxOutputTokens`。下载自管（OnDeviceModelManager：双源选源/Range 续传/字节+LITERTLM 魔数双校验），**不要用** flutter_gemma 的 fromNetwork 下载（不续传、残留孤儿分片）。估算结果带 sanity-clamp 存疑标记，只能作食物库未命中兜底。iOS 真机需 Xcode 登录 Apple ID；首次加载生成 ~0.75GiB XNNPACK cache 属正常，清理策略要保留。视觉推理（2026-09-16 拍照识别接通）：`load(enableVision: true)` + `inferWithImage`（getActiveModel supportImage → LiteRT-LM enableVision，视觉编码器固定 CPU；supportImage=false 时插件静默丢图，网关已显式拦截），服务在 `features/record/recognition/data/ondevice_food_recognition_service.dart`，识别名必须映射回食物库（未命中降级手动搜索），模型估值只作存疑判定不入账。
- **食物详情页（阶段 E，2026-09-17 入库）**：搜索结果点击 → `features/record/presentation/food_detail_sheet.dart` 底部弹层（热量大字卡 + 三大营养素**供能比例**三圆环（4/4/9 换算，带 2.25 倍人话注释，非重量比例）+ 红绿灯徽标 + 明细折叠区 + 份量入账）。红绿灯复用 D-05 `classifyVerdict`（p = 每100g 值 ÷ 当日目标 × 100），**聚合只取高侧落区**（redLow/yellowLow 对单个食物不构成警告，红色只表警告）；已知局限：完成率阈值对每100g 食物区分度弱，徽标绝大多数为绿，按热量密度的食物分级待规格新增 + 营养背书。纯函数在 `features/record/domain/`（`macro_energy.dart` / `food_signal.dart`）；弹层确认走 `_openFoodDetail` 回填既有 `_confirm` 链路（乐观更新 + D-11 撤销 + 埋点不变）。份量双轨（口语化单位）未做——食物库无份量单位数据。薄荷走查收尾（2026-09-18）：弹层加「数据有误？」纠错入口（`startFoodCorrectionFlow`，预填当前值提交 `POST /v1/foods/:id/correction`，kind=correction 入同一审核池，管理台原值 vs 建议值对照，approve 应用建议值到共享食物行；FoodCandidate 增 `suggestion` JSON 列）+ 餐次 chips；记录页今日记录按餐次分组（FoodEntries 增 `mealType` 可空列，schema v8，纯本地不上行；智能预判 `features/record/domain/meal_type.dart`：5-10 早 / 10-15 午 / 15-21 晚 / 其余加餐，历史无餐次归「其他」）。
- **用户偏好跨端同步（D-21，2026-09-18 入库）**：用户级偏好（语言/主题/体重单位/运动目标）随账号同步，设备级状态（AI 配置/密钥、模型下载、健康授权、通知权限、账号标识缓存）留本机不进包。服务端 User 增 `settingsPrefs` JSON 列（PATCH /users/me 字段级 LWW 整包替换，PATCHABLE/userView 已贯穿双驱动）。客户端协调器 `features/settings/application/settings_prefs_sync.dart`：同步包键约定 `{locale, theme, weightUnit, burnGoalKcal, stepsGoal, syncedAt}`（新增键只追加，pull 缺键跳过/非法值忽略）；push=四个偏好 provider 变更经 ref.listen 整包上行（失败静默），pull=登录成功/启动恢复会话下行（远端 syncedAt 新于本地 lastPrefsSyncedAt 才应用，回环靠 applying 标志）。Provider 懒加载——pull 挂接点（main/login/register）首次读取后 push 监听才生效。

## 后端（eatwise_server/）

```bash
npm run start:dev    # 默认内存 DataStore（STORE_DRIVER=memory）
npm test             # 单测；RUN_PG_TESTS=1 + DATABASE_URL 时含 pg 集成
npm run test:e2e
```

- 真实库：`docker compose up -d postgres && npx prisma migrate deploy`，`STORE_DRIVER=prisma` 启动。
- 云主机自部署：`Dockerfile` + `docker-compose.prod.yml` + `deploy/`（Caddyfile/env 模板）已入库，完整步骤见 `docs/tech/部署-云主机自部署-v1.0.md`。
- 持久化（2026-09-08 收口完成）：业务 Service 全部走 StoreDriver 接口，`STORE_DRIVER=prisma` 即真实落库（含用户/令牌/断食/饮食/饮水/体重/streak/帖子/点赞举报/审核队列/自定义食物/幂等键）；仅 smsCodes（mock）与管理端登录限流保留内存。prisma 模式启动前需 `npm run prisma:seed` 灌食物库（内存模式由 main.ts 自动灌）。
- 体重记录（阶段 C，2026-09-17）：`weight_logs` 表 + `/v1/weight-logs`（POST 幂等 upsert 同 userId+date 覆写 / GET ?from&to / DELETE 软删）；客户端 WeightLogStore 按用户命名空间（v2 key，v1 全局键一次性迁移），两态 pending/synced 经 RecordSyncEngine 推拉（仅登录态）。
- 图片存储（2026-09-14 迁移完成）：`STORAGE_DRIVER=local`（默认，落 uploads/，仅单实例）/ `s3`（R2/S3 + CDN，需 `S3_BUCKET`/`S3_ACCESS_KEY`/`S3_SECRET`/`CDN_BASE_URL`，R2 另需 `S3_ENDPOINT`，缺失启动即报错）；s3 模式 GET /v1/uploads/:filename 302 到 CDN，端点契约不变。
- 管理控制台：`/admin` 静态页（`src/admin/console/index.html`，原生 JS 单文件，nest-cli assets 拷到 dist），数据走 `/v1/admin/*`。鉴权为管理员账号体系（`POST /v1/admin/auth/login` 发 12h JWT，角色 admin/reviewer，见 `src/admin/admin-auth.*`）；env `ADMIN_USERNAME`/`ADMIN_PASSWORD` 齐备时启动自动种 admin 账号，`x-admin-token` 为过渡兜底（视为 admin）。

## Git 与 CI

- **不要提交**：`eatwise_data/raw/`（213MB 原始数据，gitignored）、`.tooling/`、`node_modules/`、`dist/`。
- CI 6 job：app（format/analyze/test）、build-android、build-ios、server、server-pg（真实 pg）、data。全绿才可合入。
- 发版：`git tag v*` 推送 → 自动构建 APK + GitHub Release。

## 已知外部依赖（不要在代码里硬编）

- 推送/识别/内容审核均为 stub 或抽象层，凭据与选型见 README「待外部确认」。
- 营养公式与阈值代码里有，但属「待营养背书」状态，数值改动必须同步 `docs/specs/规格-营养规则-TDEE公式与信号灯阈值-v1.0.md`。
