# EatWise 端侧推理 Spike 报告 — Gemma4-E2B-it (.litertlm) + flutter_gemma

日期：2026-09-15 ｜ 工程：`/tmp/gemma_spike`（不入库）｜ 模型缓存：`/tmp/gemma_spike_model/gemma-4-E2B-it.litertlm`

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| flutter_gemma 能否加载 Gemma4-E2B .litertlm | **GO**。flutter_gemma 1.8.2 + flutter_gemma_litertlm 1.6.3，官方支持列表明确含 Gemma 4 E2B（2.4GB），Android 模拟器全链路实测通过；iOS 因本机 Xcode 无登录账号无法构建（非技术风险，解锁步骤见 §5），imagepilot 已在同机验证模型本身可跑 |
| 输出协议可行性 | **GO**。5 轮调优共 40 次推理，`a => b => c => d` 行格式解析成功率 **100%**（宽松正则） |
| 数值质量 | 量级正确率约 80%（10 食物 8 个合理），存在单品类顽固性错误（香蕉碳水 79g）；**定位只能是食物库未命中时的兜底估算，需代码侧 sanity-clamp** |
| 是否需自写 platform channel | 不需要。flutter_gemma_litertlm 就是 LiteRT-LM 原生运行时的 FFI 封装，与 imagepilot/yiren 手写的原生桥等价 |

## 1. 模型与下载

| 项 | 值 |
|---|---|
| 文件 | gemma-4-E2B-it.litertlm（单文件，无 mmproj） |
| URL（国内优先） | `https://modelscope.cn/models/litert-community/gemma-4-E2B-it-litert-lm/resolve/master/gemma-4-E2B-it.litertlm` |
| 字节数 | 2,588,147,712（2.41 GiB）✅ 与 imagepilot 记录一致 |
| 魔数 | 前 8 字节 ASCII `LITERTLM`（4C 49 54 45 52 54 4C 4D）✅ 实测吻合 |
| Mac curl 下载 | ~5 分钟（约 8-9 MB/s，ModelScope 直连阿里云 OSS，免 token） |
| 内存门槛（imagepilot 经验值） | iOS 物理内存 ≥3000MB 放行；Android ≥3800MB（4GB+ 机型），原生侧另查 availMemory 兜底 |

## 2. flutter_gemma 支持性调研（pub.dev / fluttergemma.dev，2026-09-15 版本）

- **模块化**：`flutter_gemma`（core，不含引擎）+ `flutter_gemma_litertlm`（.litertlm FFI 引擎）。只装 core 会在 createModel 时报"add the engine package"。
- SDK 约束：Dart >=3.12.0 <4.0.0、Flutter >=3.44.0 —— 与 EatWise 内置 3.44.8 / Dart 3.12.2 匹配。
- 关键 API（均已实测）：
  ```dart
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  await FlutterGemma.installModel(modelType: ModelType.gemma4,   // Gemma4 专用枚举
      fileType: ModelFileType.litertlm)                          // 必须显式！默认 task→MediaPipe 必败
    .fromNetwork(url).withProgress((p) => ...).install();
  final model = await FlutterGemma.getActiveModel(
      maxTokens: 2048,                       // 上下文窗口(KV cache)，.litertlm 最低 1024
      preferredBackend: PreferredBackend.cpu);
  final chat = await model.createChat(
      temperature: 0.15, topK: 1, randomSeed: 42,
      systemInstruction: sys, maxOutputTokens: 96);  // 限输出长度用这个，别动 maxTokens
  await chat.addQueryChunk(Message.text(text: user, isUser: true));
  final resp = await chat.generateChatResponse();    // TextResponse.token 取文本
  await chat.session.close();
  ```
- 平台要求：iOS ≥15.0（不用 mediapipe 包；Flutter 3.44 模板默认已是 15.0）；Info.plist 加 `UIFileSharingEnabled`；大模型建议 Runner.entitlements 三项内核 key（§5 有签名坑）。Android：纯 FFI 无 gradle 插件，官方建议 `ndk { abiFilters 'arm64-v8a' }`，GPU 才需 manifest OpenCL 声明，CPU-only 全免。`largeHeap="true"` flutter 模板自带。
- 生成全局串行；手机端大模型官方建议单会话 close+recreate（每并发 session 上下文 100-500MB）。

## 3. Spike 工程

- `/tmp/gemma_spike`：flutter create + 上述两依赖，单页面（下载进度→加载→食物输入/快捷 chips→推理→时间戳日志，全部 `debugPrint('[SPIKE] ...')`）。
- `--dart-define=AUTOTEST=true --dart-define=FOODS=a,b,c` 无人值守模式：安装检查→（需则下载）→加载→逐个推理。
- Prompt 页面内可改，免重编译。`dart analyze` 零 issue。EatWise 仓库零改动（git status 干净）。

## 4. Android 模拟器实测（eatwise_test，arm64，Android 36，RAM 6144MB）

构建：`GRADLE_USER_HOME=/tmp/gemma_spike/.gradle-home flutter build apk --debug`（隔离原因见 §7-9）。

| 指标 | 实测 |
|---|---|
| 下载（应用内 ModelScope） | 9 分 52 秒（含 2 次连接中断自动重试；有效 ~4.4 MB/s。模拟器网络叠加 background_downloader 开销，Mac 直连裸速 ~9 MB/s） |
| 冷加载（首次，建 XNNPACK cache） | **3.2s**（activeBackend=cpu） |
| 热加载（后续启动，cache 已建） | **0.4-0.9s** |
| 推理延迟 | 首次 1.2-1.6s，稳态 **0.7-1.0s**/次（prefill ~120 token + 输出 ~15 token） |
| 内存 | VmRSS 稳定 ~2.0GB（模型 mmap），5 轮无增长；MemAvailable 3.6GB；**零 OOM/零 LMK 杀进程** |
| 磁盘 | 模型 2.41GiB + xnnpack_cache 0.75GiB ≈ **3.2GiB**（另有插件失败重试残留的孤儿分片 ~2GB 未清理，见 §7-5） |
| 解析成功率 | 40/40 = 100%（5 轮 × 7-10 食物，含中英混合输入） |

注：模拟器跑在 arm64 Mac 宿主机上，推理速度偏乐观；真机（尤其 4GB iPhone 13 纯 CPU）会明显慢——imagepilot 经验是「能跑但较慢」，以真机复测为准。

## 5. iPhone 真机实测（00008110-001C359E2E52801E，iPhone 13 / iOS 26.6.2）

**状态：阻塞（非技术问题）——本机 Xcode 没有登录任何 Apple ID，且已无任何包含该设备的 provisioning profile。**

经过：
1. `flutter build ios --release`（签名团队 CCTFP9X3SW + 三项内存 entitlement）→ 报通配自动签名 profile（`iOS Team Provisioning Profile: *`）**不含 Increased Memory Limit 等能力**（4 条 capability 错误）。
2. 删除该陈旧通配 profile 让 Xcode 重签 → 报 **"No Accounts"**：Xcode 无任何登录账号（keychain 无 Xcode-Token、`IDEProvisioningTeams` 为空），CLI 无法重建 profile。
3. 全盘扫描 150+ 缓存 profile：无一包含此设备 UDID（imagepilot 此前能装应是账号在登录态时完成的，后被退出）。

解除阻塞（需用户 1 分钟操作）：
1. Xcode → Settings → Accounts → `+` 登录 Apple ID（CCTFP9X3SW 或 L35RLT89XN 任一）。
2. `cd /tmp/gemma_spike && flutter build ios --release`（自动签名会重建通配 profile；付费团队可自动开通内存 entitlement 能力）。
3. 若新 profile 仍不含 entitlement 能力 → 删掉 `ios/Runner/Runner.entitlements` 里两个 `increased-*` key（或整文件）重建：**imagepilot 在同机 4GB iPhone 13 无任何特殊 entitlement 已验证 Gemma4-E2B 纯 CPU 可跑**，entitlement 是保险不是门槛。
4. 安装：`xcrun devicectl device install app --device 00008110-001C359E2E52801E build/ios/iphoneos/Runner.app`（手机保持解锁），进 App 点「1 下载模型 → 2 加载 → 3 推理」即可，日志页有全部计时。

iOS 侧配置已全部就绪：entitlements 文件、Info.plist（UIFileSharingEnabled/NSLocalNetworkUsageDescription）、deployment target 15.0、签名团队 CCTFP9X3SW。

## 6. Prompt 调优（temperature=0.15, topK=1, seed=42, maxOutputTokens=96）

五轮演进（每轮 7-10 食物）：

| 版本 | 策略 | 结果 |
|---|---|---|
| v1 | 严格格式 + 红烧肉 few-shot 示例 | 格式 5/5；但**逐字照抄示例**（红烧肉输出=示例），米饭按生米 360kcal 估 |
| v2 | 去示例 + 食用状态说明 | 格式 7/7；数值反而漂移（apple 19kcal、鸡胸肉碳水 23g），米饭仍按生米 |
| v3 | + 点值锚点（熟米饭 116/苹果 53/可乐 43） | 锚点食物全对，但**锚点引力**：香蕉/西瓜/西兰花全被吸到 53/116，鸡蛋飞出 787kcal |
| v4 | 锚点改**区间**（蔬菜 20-50、水果 30-90、熟主食 110-150…） | 8/10 量级合理，鸡蛋修复 157kcal；剩香蕉碳水 79g、可乐脂肪 3.5g |
| v5 | + 通用规律（蔬果碳水≤25g/100g、纯饮料脂肪蛋白为 0） | **8/10 合理**，可乐修复；香蕉仍 79g（模型顽固先验，prompt 救不回） |

**最终定稿（v5）**：

```
System:
你是营养成分估算助手。用户给出一个食物名称，你估算其每100克可食部的营养。按通常食用状态估算：米饭、面条等主食指煮熟后的成品，菜名指烧制完成的成品菜，肉蛋水果按生鲜。务必折算到100克：即使食物通常按瓶、罐、个出售（如一罐可乐330毫升、一个鸡蛋50克），也只估算100克的量。常见食物每100克热量参考范围：蔬菜20-50千卡，水果30-90千卡，熟主食110-150千卡，瘦肉蛋100-200千卡，肥肉菜品250-500千卡，含糖饮料35-50千卡。一般规律：新鲜水果蔬菜水分高，碳水化合物通常不超过25克/100克（干果除外）；可乐、果汁等纯饮料的脂肪和蛋白质为0。只输出一行，格式为四个数字用 => 分隔：热量 => 蛋白质 => 碳水 => 脂肪，单位分别是千卡、克、克、克。只写数字和 =>，不要任何其他文字。

User 模板:
食物：{food}
每100克营养：
```

**解析正则（宽松，全文本取第一组匹配；容忍尾部多余 `=>` 与杂质）**：
```regex
(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)
```

**v5 十食物实测原文（Android 模拟器）**：

| 食物 | 输出原文 | 解析 | 评价（参考值） |
|---|---|---|---|
| 红烧肉 | `250 => 20 => 25 => 20` | ✓ | ~可接受（热量略低，碳水偏高；参考 300-500kcal） |
| apple | `32 => 0.3 => 8.5 => 0.2` | ✓ | 偏低（参考 53/0.3/14/0.2） |
| 米饭 | `130 => 2.7 => 30.5 => 0.3` | ✓ | ✔ 正确（参考 116-130） |
| 鸡胸肉 | `150 => 30 => 0 => 3` | ✓ | ✔ 正确 |
| 鸡蛋 | `148 => 13 => 11 => 10` | ✓ | 热量/脂肪 ✔，碳水偏高（参考 1.1） |
| 西兰花 | `20 => 2.5 => 4.5 => 1.0` | ✓ | ✔（参考 34） |
| 可乐 | `35 => 0 => 8 => 0` | ✓ | ✔（参考 43/0/10.6/0） |
| 香蕉 | `320 => 2.3 => 79 => 0.3` | ✓ | ✘ 顽固错误（参考 89/1.1/22.8/0.3） |
| 豆腐 | `100 => 7 => 3 => 1 =>` | ✓（容忍尾缀） | ✔ |
| 西瓜 | `30 => 0.5 => 8 => 0.4` | ✓ | ✔（参考 30/0.6/7.6/0.2） |

**代码侧必须加的 sanity-clamp**（正式开发）：碳水/蛋白质/脂肪 >60g/100g、或四项热量与宏量营养素热量（4/4/9 kcal/g）偏差 >50% 时标记「估算存疑」走人工确认；香蕉型顽固错误靠这条兜底。

## 7. 正式开发坑清单

1. **fileType 必须显式 `ModelFileType.litertlm`**（默认 task→MediaPipe，加载即败）；`ModelType.gemma4` 有专用枚举别用 gemmaIt。
2. **core 无引擎**：`flutter_gemma` + `flutter_gemma_litertlm` 都装，initialize 注册 `LiteRtLmEngine()`。
3. **maxTokens 是上下文窗口不是输出长度**（.litertlm 最低 1024，自动钳位）；限输出用 createChat `maxOutputTokens`。
4. **iOS 内存 entitlement ↔ 签名耦合**：加三项内核 key 后要求 profile 有对应能力，陈旧通配 profile 会报 capability 缺失；删旧 profile 重建即可（前提 Xcode 有登录账号）。**4GB 机型无 entitlement 也能跑**（imagepilot 实证），签名卡壳时敢于回退。当前本机 Xcode 无账号，EatWise iOS 真机构建前先登录。
5. **下载必须自管**：flutter_gemma 的 fromNetwork 失败重试**不续传且残留孤儿分片**（实测残留 ~2GB），无魔数校验。正式方案照 imagepilot `ensureLargeModel`：Range 断点续传 + .part + 416 容错 + `LITERTLM` 魔数校验 + 字节数校验，下完 `fromFile(path)` 安装。iOS 另需磁盘预检（模型+cache ≈3.2GiB，加下载临时峰值需 ~6GiB 余量）。
6. **XNNPACK cache**：首次加载在 app_flutter 生成 ~0.75GiB `*_xnnpack_cache`，属正常，别误判为泄漏；清缓存策略要保留它（删了下次冷加载重建）。
7. **推理串行**：全局单并发；手机端单会话 close+recreate，别开 openSession 并发。
8. **CPU 显式指定**：`preferredBackend: PreferredBackend.cpu`（imagepilot 实测 iOS Metal 建不了会话；模拟器实测 cpu 生效）。
9. **Gradle 缓存损坏**：`NoSuchFileException .../transforms/.../gradle-1.0.0.jar`（flutter-plugin-loader transform 元数据损坏）删 `~/.gradle/caches/9.1.0` 不愈，**直接 `GRADLE_USER_HOME=<项目内目录>` 隔离重建**，一次成功。
10. **数值质量预期管理**：2B 模型营养估算量级正确率 ~80%，有顽固单品错误（香蕉）。产品定位：本地食物库（eatwise_data）为主、LLM 估算为未命中兜底 + sanity-clamp + 用户可编辑确认，不能当精确值入库。
11. **Android 发版**：`abiFilters 'arm64-v8a'` 限制分发；`largeHeap=true`；安装包外另需 3.2GiB+ 运行时存储，低端机门槛建议沿用 imagepilot 的 3800MB RAM 放行线。
12. **iOS 安装包体积**：flutter_gemma_litertlm 以 native-assets dylib 进包，Runner.app 体积会涨（本 spike 未细量，正式集成时补测）。

## 8. 工作量修正建议（供排期参考）

- 模型管理（下载/校验/续传/清理/磁盘预检）：imagepilot 逻辑可平移，**~2-3 天**（含双端真机回归）。
- flutter_gemma 集成 + 推理封装（含 sanity-clamp、解析、超时、OOM 兜底文案）：**~1-2 天**。
- Prompt 已定型可直接用，无需再排调优期；但需加「估算存疑」UI 流转，**~1 天**。
- iOS 签名/entitlement 与发包验证（含 TestFlight 一轮）：**~0.5-1 天**（当前 Xcode 无账号是前置条件）。
- 合计比「接个 SDK 就完」多约 2 天，主要花在下载健壮性与双端真机内存回归（4GB iPhone / 4GB Android 各一轮）。

## 9. 环境副作用披露（本次 spike 对用户机的改动）

1. 删除了 1 个陈旧通配开发 profile（团队 CCTFP9X3SW，`iOS Team Provisioning Profile: *`）——Xcode 登录账号后会自动重建，imagepilot/yiren 下次真机构建不受影响（但也需要先有登录账号）。
2. 删除了 `~/.gradle/caches/9.1.0`（损坏的 transform 缓存）——EatWise 下次 Android 构建会自动重建（首次构建变慢属正常）。spike 自己的依赖隔离在 `/tmp/gemma_spike/.gradle-home`，与 EatWise 互不污染。
3. `/tmp` 占用：模型 2.4GB + spike 工程/gradle home ~3GB + 模拟器内应用数据 ~5GB，重启自动清理或手动 `rm -rf /tmp/gemma_spike*`。
