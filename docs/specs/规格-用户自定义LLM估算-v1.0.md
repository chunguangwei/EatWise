# 规格 — 用户自定义 LLM 估算（App 直连）v1.0

> 状态：已评审（2026-08-14 设计确认：双端逻辑一致）
> 关联：PRD v1.1 M3 自定义食物；服务端 `src/llm/`（本规格不改服务端）

## 1. 目标与背景

现状：自定义食物的「AI 估算」只能走服务端 `/foods/estimate`，LLM 供应商由管理员在控制台统一配置（stub 时全体用户降级手动填写）。

目标：把 LLM 配置能力下放到移动端，用户可配置自己的 OpenAI 兼容端点（典型场景：局域网 Ollama `http://192.168.x.x:11434/v1`），App 直连用户模型完成营养估算。

已确认决策：

- **D-本-01** 未配置用户模型时回落服务端 `/foods/estimate`（两条链路共存）
- **D-本-02** 配置仅本机存储，不做云同步（apiKey 上云有合规成本；局域网端点与设备网络环境绑定）
- **D-本-03** iOS 与 Android 逻辑设计一致（差异仅限原生网络放行配置）

## 2. 架构与数据流

```
custom_food_sheet ──estimate──▶ FoodEstimateOrchestrator（新）
                                   │
                    已配置? ──yes──▶ UserLlmClient.estimate（直连用户端点）
                       │no                     │任意失败
                       ▼                       ▼
                    CustomFoodRemote.estimate（服务端 /foods/estimate）
                                   │失败
                                   ▼
                          现有「估算暂不可用，请手动填写」降级 UI
```

- 直连失败回落服务端时，toast 提示「你的模型连接失败，已改用云端估算」（新增 i18n key `record.customFood.estimateFallbackNotice`）。
- 估算结果语义不变：badge「AI 估算，请确认」、low confidence 提示、用户改动估算值后按 manual 保存。

## 3. 新增模块 `lib/core/llm/`

| 文件 | 职责 | 依赖 |
|------|------|------|
| `llm_config.dart` | `LlmConfig` 实体（provider / baseUrl / model / apiKey?）；presets 与服务端 `PROVIDER_PRESETS` 对齐（deepseek / qwen / kimi / custom）；baseUrl/model 必填校验（custom 全手填，内置供应商留空补 preset） | 无 |
| `llm_config_store.dart` | 本机持久化读写/清除；apiKey → `flutter_secure_storage`（模式同 `SecureTokenStore`），其余字段 → `SharedPreferences`（模式同 `FoodSeedLoader`） | core/secure 模式 |
| `user_llm_client.dart` | `UserLlmClient.estimate(name, {description})`：dio 直连 `POST {baseUrl}/chat/completions`，15s 超时；SYSTEM_PROMPT 与解析逻辑移植自服务端 `openai-compatible.provider.ts`（容忍 ```json 包裹、字段缺失/非数值拒绝、营养值越界拒绝） | dio |

复用现有 `FoodEstimate` / `NutritionSnapshot` 模型，不新增 DTO。

编排器 `FoodEstimateOrchestrator` 放 `features/record/custom_food/domain/`，输入 `LlmConfig?` + 两个估算源，输出 `FoodEstimate`；`custom_food_sheet` 的 `customFoodRemoteProvider.estimate` 调用点改为编排器。

## 4. 设置页

Settings 新增「AI 模型」入口 → `AiModelSettingsPage`：

- provider 下拉：custom（默认）/ deepseek / qwen / kimi
- baseUrl、model 文本框（选内置供应商时留空显示 preset 占位）
- apiKey 密码框（留空 = 保持不变，同服务端控制台语义）
- 「测试连接」按钮：`GET {baseUrl}/models` 验证连通性 + 鉴权，结果显示成功/失败 snackbar
- 「清除配置」按钮：删除全部字段回退服务端链路
- 文案全走 i18n（`i18n/strings_zh-CN.i18n.json` / `strings_en.i18n.json`，新增 `settings.aiModel.*` 段），禁止硬编码

## 5. 原生配置

- **iOS** `ios/Runner/Info.plist`：加 `NSAppTransportSecurity → NSAllowsLocalNetworking = true`（仅放行局域网 http，不全开 ATS；域名合规不变）
- **Android**：已 `usesCleartextTraffic="true"`，不动

## 6. 错误处理矩阵

| 场景 | 行为 |
|------|------|
| 未配置 | 直接走服务端（与现状一致） |
| 直连超时/不可达/非 200/非法 JSON/营养值越界 | 回落服务端 + fallback toast |
| 服务端也失败 | 现有 `isEstimateUnavailable` 降级 UI |
| 测试连接失败 | snackbar 报错原因（连通/鉴权/超时），不影响已存配置 |

apiKey 禁止写日志（同 TokenStore 约束）。

## 7. 测试

- `user_llm_client`：mock dio —— 成功 / ```json 包裹 / 字段缺失 / 越界值 / 超时 / 非 200
- 编排器：已配置直连成功 / 直连失败回落服务端 / 未配置直走服务端 / 双失败降级
- `llm_config_store`：读写 / 清除 / apiKey 留空保持不变 / preset 补全
- 设置页 widget 测试：表单校验 + 测试连接按钮状态流转
- 门禁：`dart format .` + `dart analyze` 零 issue + `flutter test` 全绿

## 8. 明确不做（YAGNI）

- 客户端估算缓存（本地 Ollama 免费快速）
- 配置云同步（D-本-02）
- 通用 AI 设置框架（本次只服务估算，模块边界留好扩展位）
- 服务端任何改动
