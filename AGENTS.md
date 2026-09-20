# AGENTS.md — 开发协作速查

> 给后续开发者与 AI 代理的实操指南。决策一律以 `docs/00-决策记录-开放问题拍板-v1.0.md`（D-01~D-20）为锚点；本文只讲「怎么跑起来、哪些坑不能踩」。

## 环境

- **Flutter SDK 内置**：`.tooling/flutter/bin`（3.44.8 / Dart 3.12.2），不要依赖系统 Flutter。所有命令先 `export PATH="$PWD/.tooling/flutter/bin:$PATH"`。
- **Android**：需 JDK 17+。系统 Java 版本不够时用 Android Studio 自带 JBR：
  `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`。
- **国内网络**：Android 依赖下载慢/卡死时 `export USE_CN_MIRRORS=1`（阿里云镜像）。CI（海外 runner）严禁开启。
- **iOS 真机**：Xcode → Settings → Accounts 需登录 Apple ID；项目签名团队 `L35RLT89XN`（注：实际现行团队 CCTFP9X3SW "jing chang"，bundleId com.jingchang.eatwise）；部署目标 iOS 15.0。
- **iOS 构建（2026-09-18 起 CocoaPods 回归）**：`open_filex` 无 SPM 支持，Pods 重新启用（仅此一个 pod）。Podfile 必须保持 `platform :ios, '15.0'` + post_install 强制 IPHONEOS_DEPLOYMENT_TARGET=15.0——低版本会造成 release 构建/签名静默失败（踩过）。新增只支持 CocoaPods 的插件时：pod install → 真机构建验证 → 提交 Podfile/Podfile.lock/pbxproj/workspace（Pods/ 目录本身 gitignored）。

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
- **端侧小模型 AI 估算（2026-09-15 核心层入库）**：`lib/core/llm/ondevice/`——Gemma4-E2B `.litertlm`（2.41GB，按需下载）。依赖 `flutter_gemma` + `flutter_gemma_litertlm` 必须成对（core 无引擎）；安装必须显式 `ModelFileType.litertlm`；`maxTokens` 是上下文窗口、限输出用 createChat `maxOutputTokens`。下载自管（OnDeviceModelManager：双源选源/Range 续传/字节+LITERTLM 魔数双校验），**不要用** flutter_gemma 的 fromNetwork 下载（不续传、残留孤儿分片）。估算结果带 sanity-clamp 存疑标记，只能作食物库未命中兜底。iOS 真机需 Xcode 登录 Apple ID；首次加载生成 ~0.75GiB XNNPACK cache 属正常，清理策略要保留。视觉推理（2026-09-16 拍照识别接通）：`load(enableVision: true)` + `inferWithImage`（getActiveModel supportImage → LiteRT-LM enableVision，视觉编码器固定 CPU；supportImage=false 时插件静默丢图，网关已显式拦截），服务在 `features/record/recognition/data/ondevice_food_recognition_service.dart`，识别名必须映射回食物库（未命中降级手动搜索），模型估值只作存疑判定不入账。音频推理（2026-09-19 端侧 ASR 接通）：`load(enableAudio: true)` + `inferWithAudio`（supportAudio → LiteRT-LM enableAudio，litertlm FFI 全链路支持；supportAudio=false 时插件静默拒音频，网关同款显式拦截）；录音用 `record` 7.1.1 插件（16kHz 单声道 PCM16 裸数据，Dart 层封 WAV 头，见 `features/record/recognition/domain/ondevice_asr_logic.dart`）；系统 ASR 不可用（无 GMS）时语音录入走端侧录音转写面板。⚠️ **E2B .litertlm 是否内置音频塔未实证**：若模型不含音频编码器，supportAudio 加载/推理会失败，需真机验证；失败时服务返回 null，语音入口回落降级卡。
- **食物详情页（阶段 E，2026-09-17 入库）**：搜索结果点击 → `features/record/presentation/food_detail_sheet.dart` 底部弹层（热量大字卡 + 三大营养素**供能比例**三圆环（4/4/9 换算，带 2.25 倍人话注释，非重量比例）+ 红绿灯徽标 + 明细折叠区 + 份量入账）。红绿灯复用 D-05 `classifyVerdict`（p = 每100g 值 ÷ 当日目标 × 100），**聚合只取高侧落区**（redLow/yellowLow 对单个食物不构成警告，红色只表警告）；已知局限：完成率阈值对每100g 食物区分度弱，徽标绝大多数为绿，按热量密度的食物分级待规格新增 + 营养背书。纯函数在 `features/record/domain/`（`macro_energy.dart` / `food_signal.dart`）；弹层确认走 `_openFoodDetail` 回填既有 `_confirm` 链路（乐观更新 + D-11 撤销 + 埋点不变）。份量双轨（口语化单位）未做——食物库无份量单位数据。薄荷走查收尾（2026-09-18）：弹层加「数据有误？」纠错入口（`startFoodCorrectionFlow`，预填当前值提交 `POST /v1/foods/:id/correction`，kind=correction 入同一审核池，管理台原值 vs 建议值对照，approve 应用建议值到共享食物行；FoodCandidate 增 `suggestion` JSON 列）+ 餐次 chips；记录页今日记录按餐次分组（FoodEntries 增 `mealType` 可空列，schema v8，纯本地不上行；智能预判 `features/record/domain/meal_type.dart`：5-10 早 / 10-15 午 / 15-21 晚 / 其余加餐，历史无餐次归「其他」）。
- **重装登录恢复两连修（2026-09-19 走查）**：① 引导重弹根因——`_applySession` 只写内存 OnboardingGate 不持久化，杀进程重开冷启动从 SharedPreferences 读 false 再进引导；修复=服务端 onboardingStatus（completed/skipped，登录/注册响应已带）下行时**内存门禁+`OnboardingStore.markOnboardingCompleted()` 双写**（AuthController 增 `onboardingStore` 可选参，auth_providers 装配，时序先于路由翻转）。②「有记录但首页不显示」根因——`/sync/pull` 下行入库（`RemoteRecordSync._applyChange`）从不重算 `daily_nutrition_caches`（首页今日汇总/信号卡唯一数据源，缓存只在本地入账/撤销时重算）；修复=`_pullPages` 收集受影响归属日统一 `recomputeDailyNutrition`（含 tombstone 软删回落）。③ ②的存量盲区（v1.12.5 走查）：旧版本已下行记录游标已越过，pull 无新变更 → 缓存永远缺失不自愈（数据页近 7 日趋势 `weeklyTrendProvider` 读同一缓存表，一并假空）；修复=`DailyNutritionCacheRepair`（`features/record/data/daily_nutrition_cache_repair.dart`：缓存缺失或 entries.updatedAtUtc 新于 cache 即重算，幂等）挂 RecordSyncEngine finally 路径（**不依赖在线/有无变更**）——每用户首次全量回填（prefs `daily_cache_backfill_v1_<userId>` 标记），之后每次 syncNow 只扫近 7 天廉价窗口。
- **手动记运动（2026-09-19 入库）**：无 GMS 设备（鸿蒙等 Health Connect 不可用）手动兜底。MET 系数表 + kcal 估算（MET × 体重kg × 时长h，体重缺省 60kg 兜底并 UI 标注）+ 系统/手动合并纯函数（`mergeBurnKcal` / `mergeSteps` / `estimateKcalFromStepsWalk`：体重 × 距离 × 1.036，距离缺省 步数 × 0.75m 步幅，常量〔待营养背书〕）在 `features/health/domain/exercise_types.dart`；类型表 17 种。drift `exercise_logs`（schema **v12**；v10 补 `source`，v11 补 `steps` 步数持久化，v12 补两态同步字段 clientRequestId/serverId/syncState/deleted——历史行幂等键回填=localId）。**服务端上行（同日拍板）**：prisma `exercise_logs` 表（migration 20260919140000，随下次部署 `prisma migrate deploy`），复用 /sync/push|pull 体系（entity=exerciseLog，轻量两态仅 create/delete 无 update——运动记录无编辑场景，改=删了重记；pull 随行 `exerciseLogChanges`，口径与 waterLog 完全一致；U3 导出/U5 清除已含）。客户端 `RemoteExerciseLogSync`（`features/health/data/`）挂 RecordSyncEngine（仅登录态上行，匿名本地 pending 保留；删除=未上行物理删/已上行 tombstone 上行 delete op；下行不覆盖本地 pending）。**合规边界不变**：系统健康数据（HealthKit/Health Connect 实时步数）仍不落盘不上行，仅用户主动录入/截图确认的记录同步。仓储/Provider 在 `features/health/data|application/exercise_log_*`；记录页快捷操作区第五入口「记运动」→ 弹层 `exercise_log_sheet.dart`（走路可按步数录入自动换算热量）。首页预算行/数据页消耗环=系统+手动合计（mergeBurnKcal），数据页步数=系统步数+当日落库合计（mergeSteps）；unsupported 无步数显「—」+引导。**截图导入**：弹层「拍照识别/相册导入」→ 端侧视觉严格 JSON（`exercise_screenshot_logic.dart`）→ 可编辑确认弹层落库（source='screenshot'，步数随记录）。**展示缺项走查**：里程碑分享卡「80% 的伙伴」虚假分位已改自我鼓励口径。
- **APK 分发链路（2026-09-19 终版，仓库 public）**：**更新检测直连 GitHub**（`UpdateChecker` 裸 Dio 调 `api.github.com/repos/chunguangwei/EatWise/releases/latest`，不经服务端；匿名 60 次/小时/IP + ≥24h 节流；iOS 平台门不请求）。**下载在端内**（`update_downloader.dart`）：主链 GitHub asset CDN，兜底常量 `AppVersionInfo.selfHostedApkFallbackUrl`（VPS apk-sync 托管）；断点续传（.part+Range，206 追加/200 截断/416 完整）+ 每 URL 3 次退避重试 + 主链耗尽切兜底 + wakelock_plus 保活 + 完成大小校验。服务端 `/v1/app/version/latest` 保留但客户端已不再调用。apk-sync 保留（兜底托管）；**同版本号换包需先 `rm eatwise_server/downloads/.version` 再 up apk-sync**。CI release.yml = release 构建 + secret `KEYSTORE_BASE64`（本机 debug.keystore）签名，与本地产物同源；写入步骤有 sha256sum+keytool 指纹自检（基线：keystore `daa4ea6b…` / 证书 `79:94:78:99:…:B1:95`）。
- **生产安全基线（2026-09-19）**：公网仅 8443+22；`SMS_MOCK_ENABLED=false` 已上生产（mock 验证码 123456 链路关闭，501 SMS_CHANNEL_UNAVAILABLE，短信通道接入前手机号登录/注册不可用）；ADMIN_TOKEN 未配（x-admin-token 兜底关闭）；fail2ban 守 sshd。
- **用户偏好跨端同步（D-21，2026-09-18 入库）**：用户级偏好（语言/主题/体重单位/运动目标）随账号同步，设备级状态（AI 配置/密钥、模型下载、健康授权、通知权限、账号标识缓存）留本机不进包。服务端 User 增 `settingsPrefs` JSON 列（PATCH /users/me 字段级 LWW 整包替换，PATCHABLE/userView 已贯穿双驱动）。客户端协调器 `features/settings/application/settings_prefs_sync.dart`：同步包键约定 `{locale, theme, weightUnit, burnGoalKcal, stepsGoal, syncedAt}`（新增键只追加，pull 缺键跳过/非法值忽略）；push=四个偏好 provider 变更经 ref.listen 整包上行（失败静默），pull=登录成功/启动恢复会话下行（远端 syncedAt 新于本地 lastPrefsSyncedAt 才应用，回环靠 applying 标志）。Provider 懒加载——pull 挂接点（main/login/register）首次读取后 push 监听才生效。
- **未入库食品乐观入账 + 审核联动（2026-09-19 入库）**：「先记录，审批不过再清除」。服务端 `sync.service.snapshotOf` 回落本人自定义食物（此前只查共享库 → 自定义食物记录上行必 4xx → 客户端 T7 回滚静默删除，即「不报错就没了」根因；`RecordSyncFailure` 流原本无监听）；`reviewFoodCandidate` reject 幂等（重复驳回 200 返回当前态，reason 不覆写）且 kind≠correction 时级联软删贡献者该食物的 FoodEntry（`softDeleteFoodEntriesByFood`，双驱动）。客户端：`_push` 守卫（食物行缺失/customSyncPending 保持 pending 不放行吃 4xx）+ syncNow 自定义食物先于记录上行；条目营养按**快照口径**（approve/纠错改值不回溯）；「审核中」徽标复用 Foods.contributionStatus（今日记录行展示）。状态感知不做推送：`ContributionReviewSync`（`features/record/custom_food/application/contribution_review.dart`）在记录同步/进入记录页时拉「我的贡献」，diff 纯逻辑 `domain/contribution_review_logic.dart`（首次见到静默建基线，只认 pending→终态迁移）；approved 去标记、rejected 清本地记录+聚合重算+一次性驳回通知（prefs 队列 `ContributionStatusStore`，记录页 drain 展示，i18n `record.customFood.reviewRejectedNotice`）。无表结构变更（drift 仍 v10，prisma schema 不变）。
- **用户角色体系 + 移动端审批中心（2026-09-19 入库）**：User 增 `role`（'user'/'admin'，默认 user；prisma migration 20260919120000 + 双驱动贯穿；userView 带 role 但 **role 不在 PATCHABLE**——本人不可自助提权）。管理台设角色：`PATCH /v1/admin/users/:id/role`（AdminAuthGuard + @AdminRole('admin')，reviewer 403；幂等），console 用户页签角色下拉（一般用户/管理员，非 admin 身份只读禁用）。移动端审批：`GET/POST /v1/moderation/food-candidates[/:id/review]` 走**用户 JWT**（全局 JwtAuthGuard）+ `UserAdminGuard`（`src/admin/user-admin.guard.ts`，role!=admin → 403 明确提示不 404；匿名 401），复用 FoodService 同一审核池/同一 reviewFoodCandidate（含驳回级联清理）；FoodCandidate 增 `reviewedBy` 可空列留痕（管理端=管理员账号 id、token 兜底 null；移动端=用户 id）。客户端：`UserMeView.role`（缺省按 user 门控关闭）经 userMeProvider 流转；设置页账号组 role==admin 才显示「审批中心」入口（`/moderation/food-candidates` → `features/moderation/`：pending 队列游标分页 + 详情展开（纠错建议值对照）+ 通过/驳回确认弹窗 + snackbar 反馈，i18n `moderation.*`）。

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
