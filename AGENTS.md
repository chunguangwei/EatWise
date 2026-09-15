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
- **端侧小模型 AI 估算（2026-09-15 核心层入库）**：`lib/core/llm/ondevice/`——Gemma4-E2B `.litertlm`（2.41GB，按需下载）。依赖 `flutter_gemma` + `flutter_gemma_litertlm` 必须成对（core 无引擎）；安装必须显式 `ModelFileType.litertlm`；`maxTokens` 是上下文窗口、限输出用 createChat `maxOutputTokens`。下载自管（OnDeviceModelManager：双源选源/Range 续传/字节+LITERTLM 魔数双校验），**不要用** flutter_gemma 的 fromNetwork 下载（不续传、残留孤儿分片）。估算结果带 sanity-clamp 存疑标记，只能作食物库未命中兜底。iOS 真机需 Xcode 登录 Apple ID；首次加载生成 ~0.75GiB XNNPACK cache 属正常，清理策略要保留。

## 后端（eatwise_server/）

```bash
npm run start:dev    # 默认内存 DataStore（STORE_DRIVER=memory）
npm test             # 单测；RUN_PG_TESTS=1 + DATABASE_URL 时含 pg 集成
npm run test:e2e
```

- 真实库：`docker compose up -d postgres && npx prisma migrate deploy`，`STORE_DRIVER=prisma` 启动。
- 云主机自部署：`Dockerfile` + `docker-compose.prod.yml` + `deploy/`（Caddyfile/env 模板）已入库，完整步骤见 `docs/tech/部署-云主机自部署-v1.0.md`。
- 持久化（2026-09-08 收口完成）：业务 Service 全部走 StoreDriver 接口，`STORE_DRIVER=prisma` 即真实落库（含用户/令牌/断食/饮食/饮水/streak/帖子/点赞举报/审核队列/自定义食物/幂等键）；仅 smsCodes（mock）与管理端登录限流保留内存。prisma 模式启动前需 `npm run prisma:seed` 灌食物库（内存模式由 main.ts 自动灌）。
- 图片存储（2026-09-14 迁移完成）：`STORAGE_DRIVER=local`（默认，落 uploads/，仅单实例）/ `s3`（R2/S3 + CDN，需 `S3_BUCKET`/`S3_ACCESS_KEY`/`S3_SECRET`/`CDN_BASE_URL`，R2 另需 `S3_ENDPOINT`，缺失启动即报错）；s3 模式 GET /v1/uploads/:filename 302 到 CDN，端点契约不变。
- 管理控制台：`/admin` 静态页（`src/admin/console/index.html`，原生 JS 单文件，nest-cli assets 拷到 dist），数据走 `/v1/admin/*`。鉴权为管理员账号体系（`POST /v1/admin/auth/login` 发 12h JWT，角色 admin/reviewer，见 `src/admin/admin-auth.*`）；env `ADMIN_USERNAME`/`ADMIN_PASSWORD` 齐备时启动自动种 admin 账号，`x-admin-token` 为过渡兜底（视为 admin）。LLM 配置运行时覆盖存 `data/admin-config.json`（gitignored，含 apiKey），读优先级 = 覆盖 > env。

## Git 与 CI

- **不要提交**：`eatwise_data/raw/`（213MB 原始数据，gitignored）、`.tooling/`、`node_modules/`、`dist/`。
- CI 6 job：app（format/analyze/test）、build-android、build-ios、server、server-pg（真实 pg）、data。全绿才可合入。
- 发版：`git tag v*` 推送 → 自动构建 APK + GitHub Release。

## 已知外部依赖（不要在代码里硬编）

- 推送/识别/内容审核均为 stub 或抽象层，凭据与选型见 README「待外部确认」。
- 营养公式与阈值代码里有，但属「待营养背书」状态，数值改动必须同步 `docs/specs/规格-营养规则-TDEE公式与信号灯阈值-v1.0.md`。
