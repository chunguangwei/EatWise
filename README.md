# 明食 · EatWise

「懂你节奏的轻断食陪伴者」——轻断食与健康饮食 App，iOS / Android 双端，中英双语。

本仓库为 monorepo，包含产品文档、Flutter 客户端、NestJS 后端与食物库数据管线。

## 仓库结构

```
├── docs/                        # 产品与技术文档（见下）
│   ├── 00-决策记录-开放问题拍板-v1.0.md   # ⭐ 最高决策锚点（D-01~D-20）
│   ├── specs/                   # 模块规格（状态机/同步/i18n/营养/设计交付）
│   ├── tech/                    # 技术方案（架构/API 契约/埋点字典）
│   ├── compliance/              # 隐私与合规方案
│   ├── qa/                      # 测试用例（功能/边界/无障碍/双语）
│   └── plan/                    # 里程碑排期与开发准备清单
├── 轻断食与健康饮食App-产品需求文档PRD-v1.1.md  # 现行 PRD（v1.0 为历史版本）
├── 产品设计一站式协作工作流-*.md                # 设计方案定稿
├── 产品需求评审-*.md                            # 评审结论与 Gate
├── eatwise_app/                 # Flutter 客户端（iOS + Android）
├── eatwise_server/              # NestJS 后端（REST API + Prisma/PostgreSQL）
├── eatwise_data/                # 食物营养库：数据资产 + 管线 + 校验报告
└── .github/workflows/           # CI（6 job 门禁）+ 发版流水线
```

## 快速开始

### 客户端（eatwise_app）

```bash
# Flutter SDK 已内置在 .tooling/（3.44.8 stable，无需系统安装）
export PATH="$PWD/.tooling/flutter/bin:$PATH"
cd eatwise_app
flutter pub get
dart run slang                                   # i18n 代码生成（不要用 build_runner 跑 slang）
dart run build_runner build                      # drift 代码生成
flutter test                                     # 452 条测试
dart analyze                                     # 零 issue 门禁
flutter run                                      # 模拟器/真机运行
```

本地联调后端时：

```bash
# iOS 模拟器 / 真机（同 Wi-Fi，IP 换成你的局域网地址）
flutter run --dart-define=API_BASE_URL=http://<你的局域网IP>:3000
# Android 模拟器访问宿主机
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

### 后端（eatwise_server）

```bash
cd eatwise_server
npm install
npm run start:dev        # 默认内存 DataStore，启动自动加载 7455 条食物库
npm test                 # 单测（pg 集成测试需 RUN_PG_TESTS=1 + DATABASE_URL）
npm run test:e2e
# 真实 PostgreSQL 模式：docker compose up -d postgres
#   → npx prisma migrate deploy → STORE_DRIVER=prisma npm run start:dev
```

### 食物库（eatwise_data）

```bash
bash eatwise_data/scripts/fetch_usda.sh          # 拉取 USDA 原始数据（~213MB，不入库）
python3 eatwise_data/scripts/build_seed.py       # 生成 foods.seed.json + 校验报告
```

## 发版与更新

- **发版**：`git tag v1.x.x && git push origin v1.x.x` → release 流水线自动构建 APK 并创建 GitHub Release。
- **App 内更新提醒**：客户端经服务端 `/v1/app/version/latest` 检查更新（服务端代理 GitHub Releases，token 配置在服务端 env `GITHUB_RELEASE_TOKEN`），有更新弹窗提示，支持强制更新（`APP_MIN_SUPPORTED_VERSION`）。
- 当前 APK 为 debug 签名（内部测试）；正式分发前需配置 release keystore（release.yml 内已留 TODO）。

## 环境与构建注意事项（踩坑记录）

- **工程路径含中文**：已修复三处编码问题（gradle.properties JVM UTF-8、settings.gradle.kts 的 flutter.sdk 解析、.tooling SDK 内补丁）。`flutter analyze` 在中文路径下崩溃是 SDK bug，统一用 `dart analyze`。
- **国内构建加速**：Android 依赖走阿里云镜像需 `export USE_CN_MIRRORS=1`（CI 海外 runner 不可开启）。
- **Android 构建**：需 JDK 17+（本机系统 Java 11 时可用 Android Studio 自带 JBR：`export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`）。
- **iOS 最低版本**：15.0（D-14）；home_widget 要求 ≥14。真机调试需在 Xcode → Settings → Accounts 登录 Apple ID。
- **slang**：`namespaces: false`，所有 i18n key 只放 `i18n/strings_zh-CN.i18n.json` 与 `strings_en.i18n.json` 两个文件（多文件会互相覆盖），生成命令固定 `dart run slang`。

## 当前状态

- **功能**：M1–M6 全部落地（新手引导/断食计时/快捷记录/营养信号灯/streak 与社区/趋势报告），账号同步、无障碍贯穿、隐私合规基础、双端构建与 CI 门禁齐备。
- **测试**：App 452 条全绿；服务端 105 单测 + 19 e2e 全绿（Prisma 集成测试 CI 真跑）。
- **首发**：v1.0.0 已发布（GitHub Releases）。

### 待外部确认（不阻塞开发，阻塞上线）

| 事项 | 说明 |
|------|------|
| 营养背书 | TDEE 公式、红黄绿阈值、RDA、份量映射表需营养专家签字（M4 上线 Gate） |
| 法务终稿 | 隐私政策/协议文本、删除冷静期与 Apple 5.1.1 兼容性 |
| 第三方选型 | 食物识别 API、内容安全供应商、聚合推送 SDK（个推/极光） |
| 凭据 | Firebase/APNs、release keystore、Apple Developer 上架账号 |
| 数据运营 | 食物库双语条目缺口 ~2800 条翻译校对（现 172 条双语） |

## 文档索引

- 决策锚点：`docs/00-决策记录-开放问题拍板-v1.0.md`
- 开发命令与踩坑速查：`AGENTS.md`
- 各模块规格：`docs/specs/`；API：`docs/tech/后端API契约-v1.0.md`；埋点：`docs/tech/埋点规范与事件字典-v1.0.md`
- 排期与准备清单：`docs/plan/里程碑排期与开发准备清单-v1.0.md`
