# 明食 · EatWise

「懂你节奏的轻断食陪伴者」——轻断食与健康饮食 App，iOS / Android 双端，中英双语。

本仓库为 monorepo，包含产品文档、Flutter 客户端、NestJS 后端与食物库数据管线。

## 功能全览

- **断食计时**：14:10 / 16:8 / 18:6 方案 + 自选进食窗口（可跨午夜），倒计时环、延长（30min 步进、累计 ≤4h）、破窗容差判定（提前 ≤15min 算达标）；断食连胜（streak）+ 补签卡（每月 2 张、7 天窗口）+ 断签弹窗；服务端判分导致的断签有**带日期的原因告知**（SnackBar）。
- **饮食记录**：搜索（本地先行 + 远端防抖追加）、**拍照识别**、**语音录入**（系统 ASR，无 GMS 设备走端侧 ASR）、**扫码录入**、常吃快捷入口；份量入账 + 撤销；今日记录按餐次分组（智能预判）。
- **食物库与贡献**：1956 条双语食物库（《中国食物成分表》+ 策展条目）；自定义食物、纠错、贡献共享库（先审后发审核池）；**管理员移动端删除食品**（跨用户级联下架）+ Web 管理台。
- **营养反馈**：TDEE 目标（身体档案推导）、红黄绿信号灯（按当日目标完成率落区）、供能比例三圆环、数据页趋势/周报/月报。
- **健康数据**：饮水记录与整点提醒、体重记录、手动记运动（17 种 MET 系数，可拍照导入运动截图）、步数（系统数据 + 手动合并）；HealthKit / Health Connect 数据**只在设备本地读取展示，从不上传**。
- **社区**：打卡发帖（文本/图片，先审后发）、点赞、举报、**屏蔽用户**；里程碑分享卡。
- **端侧 AI**：可选下载 Gemma 端侧模型（约 2.4GB，按需下载 + Wi-Fi 确认）——拍照视觉识别、端侧语音转写、食物估算全部**本机推理，图片与音频不出设备**；也可自配 OpenAI 兼容端点（局域网 Ollama 等，key 仅存本机）；两级都不可用时降级手动填写，无服务端兜底。
- **账号与系统**：用户名+密码注册登录（手机号验证码登录当前未启用，UI 已隐藏）；用户偏好跨端同步；账号删除 = 立即吊销会话 + **7 天冷静期**（可撤销，期满物理删除）；中英双语、暗色模式；安卓 **App 内更新**（直连 GitHub Releases，断点续传，VPS 兜底），iOS 走 App Store。

## 技术栈与仓库结构

```
├── docs/                        # 产品与技术文档（见文末文档地图）
│   ├── 00-决策记录-开放问题拍板-v1.0.md   # ⭐ 最高决策锚点（D-01~D-20）
│   ├── specs/                   # 模块规格（状态机/同步/i18n/营养/设计交付）
│   ├── tech/                    # 技术方案（架构/API 契约/埋点字典/部署）
│   ├── compliance/              # 隐私政策/用户协议（海外版 v2.0）与合规方案
│   ├── qa/                      # 测试用例（功能/边界/无障碍/双语）
│   └── plan/                    # 里程碑、复工手册、App Store 审核材料
├── 轻断食与健康饮食App-产品需求文档PRD-v1.1.md  # 现行 PRD（v1.0 为历史版本）
├── eatwise_app/                 # Flutter 客户端（iOS + Android；Riverpod + drift + slang）
├── eatwise_server/              # NestJS 后端（REST API；StoreDriver 双驱动：内存 / Prisma+PostgreSQL）
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
dart run slang                                   # i18n 代码生成（唯一正确方式）
dart run build_runner build                      # drift 代码生成
dart analyze                                     # 零 issue 门禁（禁止 flutter analyze，中文路径 SDK bug 会崩）
flutter test                                     # 1433 条测试
flutter run                                      # 模拟器/真机运行
```

本地联调后端时（必须带 `/v1` 前缀）：

```bash
# iOS 模拟器 / 真机（同 Wi-Fi，IP 换成你的局域网地址）
flutter run --dart-define=API_BASE_URL=http://<你的局域网IP>:3000/v1
# Android 模拟器访问宿主机
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1
```

**iOS 真机 release 构建必须显式带生产地址**（默认 dev=localhost，真机上必失败）：

```bash
flutter build ios --release --dart-define=API_BASE_URL=https://wcg.polin.tech:8443/v1
```

### 后端（eatwise_server）

```bash
cd eatwise_server
npm install
npm run start:dev        # 默认内存 DataStore（STORE_DRIVER=memory），启动自动灌食物库
npm test                 # 单测 277 条（pg 集成测试需 RUN_PG_TESTS=1 + DATABASE_URL）
npm run test:e2e         # e2e 142 条
# 真实 PostgreSQL 模式：
docker compose up -d postgres && npx prisma migrate deploy && npm run prisma:seed
STORE_DRIVER=prisma npm run start:dev
```

**管理控制台**：`http://localhost:3000/admin`——食物众包审核、用户角色、共享食物库管理、API 配置。鉴权为管理员账号体系（`ADMIN_USERNAME`/`ADMIN_PASSWORD` 齐备时启动自动种 admin 账号，见 `.env.example`）。

### 食物库（eatwise_data）

```bash
bash eatwise_data/scripts/fetch_usda.sh          # 拉取 USDA 原始数据（~213MB，不入库）
python3 eatwise_data/scripts/build_seed.py       # 生成 foods.seed.json + 校验报告
```

## 发版与更新

- **发版**：`git tag v1.x.x && git push origin v1.x.x` → release 流水线自动构建 APK（仓库 secret `KEYSTORE_BASE64` 签名，与本机 debug.keystore 同源，写入步骤带 sha256 + keytool 指纹自检）并创建 GitHub Release。
- **App 内更新**：安卓客户端直连 GitHub `releases/latest` 检查更新，端内下载（断点续传/重试/保活），VPS apk-sync 托管兜底（同版本号换包需先 `rm eatwise_server/downloads/.version`）；iOS 走 App Store，不做更新提示。
- **iOS 装机**：本地 `flutter build ios|ipa --release` 必须带 `--dart-define=API_BASE_URL=https://wcg.polin.tech:8443/v1`（见上）。

## App Store 上架

- **范围**：海外（非欧盟）+ 港澳台；不上中国大陆、不主动面向欧盟。
- **审核材料包**：`docs/plan/AppStore-审核材料-v1.0.md`（演示账号、Review Notes、元数据、隐私标签、截图清单）。
- **公网法务页**（App Store Connect 必填）：`https://wcg.polin.tech:8443/privacy` 与 `https://wcg.polin.tech:8443/terms`（中英双文同页，由 `eatwise_server` 的 `npm run build:legal` 从 `docs/compliance/` 的 v2.0 文档生成）。联系邮箱：chunguangwee@gmail.com。
- **隐私与安全设计要点**：HealthKit / Health Connect 只读本机、从不上传；端侧 AI 本机推理，图片/音频不出端；社区内容先审后发 + 可举报可屏蔽；不面向 13 岁以下（引导有年龄确认）；无广告、无第三方追踪 SDK，埋点可关闭；账号删除 7 天冷静期。

## 环境与构建注意事项（踩坑记录）

- **工程路径含中文**：已修复三处编码问题；`flutter analyze` 在中文路径下崩溃是 SDK bug，统一用 `dart analyze`。
- **国内构建加速**：Android 依赖走阿里云镜像需 `export USE_CN_MIRRORS=1`（CI 海外 runner 严禁开启）。
- **Android 构建**：需 JDK 17+（系统 Java 不够时用 Android Studio 自带 JBR：`export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`）。
- **iOS 最低版本**：15.0。真机调试需 Xcode → Settings → Accounts 登录 Apple ID。CocoaPods 仅 `open_filex` 一个 pod，Podfile 必须保持 `platform :ios, '15.0'` + post_install 强制部署目标 15.0。
- **slang**：`namespaces: false`，所有 i18n key 只放 `i18n/strings_zh-CN.i18n.json` 与 `strings_en.i18n.json` 两个文件（多文件会互相覆盖），生成命令固定 `dart run slang`，不要装回 `slang_build_runner`。
- **法务文本四处同步**：App 内 i18n `legal.*` ↔ `docs/compliance/隐私政策|用户协议-海外版-v2.0.md` ↔ `eatwise_server/public/*.html`（改后跑 `npm run build:legal`）↔ 联系邮箱常量（含 `scripts/build_legal_pages.mjs` 的 CONTACT）。

## 当前状态

- **版本**：v1.13.31+95（App Store 提审准备完成 + 同步完整性全量收口：fastingRecord 进 /sync、契约防线、档案脏标记上行）。
- **测试**：App 1433 条全绿；服务端 283 单测 + 148 e2e 全绿（Prisma 集成测试 CI 真跑）。
- **食物库**：seed 2026.09.23，1956 条（双语 100%，CFCT 1616 + 策展 340），removedIds 累计 7328。
- **服务端**：生产在美国 VPS（`wcg.polin.tech:8443`，Caddy 反代 + Docker 自部署，见 `docs/tech/部署-云主机自部署-v1.0.md`）。

### 待外部确认（不阻塞开发，阻塞对应能力上线）

| 事项 | 现状 |
|------|------|
| 营养背书 | TDEE 公式、红黄绿阈值、MET/RDA 等常量均为通用公式估算，标〔待营养背书〕；数值改动必须同步 `docs/specs/规格-营养规则-TDEE公式与信号灯阈值-v1.0.md` |
| 推送 | 抽象层 stub（TODO），未接 APNs/FCM/厂商通道 |
| 内容审核 | 文本先审后发已上线（关键词机审 stub）；图片审核未接第三方，供应商选型待定 |
| 短信通道 | 未接入（`SMS_MOCK_ENABLED=false` 上生产），手机号登录/注册 UI 已隐藏，法务文本已如实写明 |
| 凭据与账号 | Firebase/APNs、Apple Developer / Google Play 上架账号按审核材料包推进 |

## 文档地图

- 决策锚点：`docs/00-决策记录-开放问题拍板-v1.0.md`（D-01~D-20）
- 开发命令与踩坑速查：`AGENTS.md`
- 交付记录与复工手册：`docs/plan/交付记录与复工手册-2026-W31.md`
- App Store 审核材料包：`docs/plan/AppStore-审核材料-v1.0.md`
- 法务（海外版 v2.0）：`docs/compliance/隐私政策-海外版-v2.0.md`、`docs/compliance/用户协议-海外版-v2.0.md`
- 模块规格：`docs/specs/`（营养规则、断食状态机、同步四态、i18n 等）；API：`docs/tech/后端API契约-v1.0.md`；埋点：`docs/tech/埋点规范与事件字典-v1.0.md`
- 部署：云主机自部署（现行，`docs/tech/部署-云主机自部署-v1.0.md`）；海外托管路线备选（`docs/tech/部署-海外上线-v1.0.md`）
