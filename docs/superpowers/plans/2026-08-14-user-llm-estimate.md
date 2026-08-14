# 用户自定义 LLM 估算（App 直连）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在 App 内配置自己的 OpenAI 兼容 LLM 端点（典型：局域网 Ollama），自定义食物的「AI 估算」优先直连用户模型，失败回落服务端 `/foods/estimate`。

**Architecture:** 新增 `lib/core/llm/`（配置实体/存储/直连客户端），新增 `FoodEstimateOrchestrator` 编排两级回落，Settings 新增「AI 模型」配置页。服务端零改动。规格：`docs/specs/规格-用户自定义LLM估算-v1.0.md`。

**Tech Stack:** Flutter 3.44.8（`.tooling/flutter`）/ Riverpod / dio / flutter_secure_storage / shared_preferences / slang i18n。

## Global Constraints

- 命令前 `export PATH="$PWD/.tooling/flutter/bin:$PATH"`；工作目录 `eatwise_app/`
- **禁 `flutter analyze`**（中文路径 SDK bug），用 `dart analyze`，门禁零 issue（含 info）
- i18n 只改 `i18n/strings_zh-CN.i18n.json` + `i18n/strings_en.i18n.json` 两个文件，生成固定 `dart run slang`；**禁止装 slang_build_runner**；文案禁止硬编码
- 带 action 的 SnackBar 必须显式 `persist: false`（Flutter 3.44 行为变更，本计划 SnackBar 均无 action，不受影响但不得引入）
- apiKey 禁止写日志；存储走 `flutter_secure_storage`（模式同 `lib/core/network/token_store.dart` 的 `SecureTokenStore`）
- 双端逻辑一致；原生差异仅限 iOS ATS 配置
- 提交门禁：`dart format .` + `dart analyze` 零 issue + `flutter test` 全绿
- 服务端 `eatwise_server/` 一行不动

## 关键既有签名（实施者必读）

```dart
// lib/features/record/custom_food/domain/custom_food_models.dart
final class FoodEstimate {
  const FoodEstimate({required this.per100g, required this.confidence});
  final NutritionSnapshot per100g;   // kcal/proteinG/carbG/fatG，全 double
  final String confidence;           // 'high' | 'medium' | 'low'
  bool get isLowConfidence => confidence == 'low';
}

// lib/features/record/custom_food/data/custom_food_remote.dart
abstract interface class CustomFoodRemote {
  Future<FoodEstimate> estimate(String name, {String? description});
  Future<String> createCustom(CustomFoodDraft draft, {required String clientRequestId});
  Future<String> contribute(String foodId, {required String clientRequestId});
}
bool isEstimateUnavailable(Object error); // 已有：网络/超时/503 判定

// lib/features/record/custom_food/presentation/custom_food_providers.dart
final Provider<CustomFoodRemote> customFoodRemoteProvider = ...;

// lib/core/network/api_exception.dart
final class NetworkApiException extends ApiException { const NetworkApiException([String message = '网络连接失败']); }
final class TimeoutApiException extends ApiException { const TimeoutApiException([String message = '请求超时']); }
final class BusinessApiException extends ApiException { ... code / httpStatus ... }

// lib/core/network/network_providers.dart
final Provider<Dio> apiDioProvider = Provider<Dio>((ref) { ... }); // 已装配信封/鉴权拦截器，仅用于服务端 API，勿复用于用户端点
```

路由模式：`lib/app/router/app_router.dart` 顶层 `GoRoute(path: '/legal/privacy', ...)` 同层新增。设置行组件：`settings_page.dart` 内 `_SettingsGroup` / `_SettingsTile`（私有，新页自建简单 ListTile 即可，样式 token 用 `AppColors/AppSpacing/AppTextStyles/AppRadii`）。

---

### Task 1: `core/llm` 配置实体与本机存储

**Files:**
- Create: `lib/core/llm/llm_config.dart`
- Create: `lib/core/llm/llm_config_store.dart`
- Test: `test/core/llm/llm_config_store_test.dart`

**Interfaces:**
- Produces（Task 2/3/4 依赖）:
  - `final class LlmConfig { provider, baseUrl, model, apiKey? }`、`LlmConfig.effective()`（内置供应商留空补 preset）、`bool get isComplete`
  - `const llmProviderPresets = {'deepseek': (baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat'), 'qwen': (baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus'), 'kimi': (baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k')}`（与服务端 `PROVIDER_PRESETS` 对齐，含 custom 无 preset）
  - `abstract interface class LlmConfigStore { Future<LlmConfig?> read(); Future<void> save(LlmConfig); Future<void> clear(); }`
  - `final class LocalLlmConfigStore implements LlmConfigStore`（构造注入 `FlutterSecureStorage` 与 `SharedPreferences`）
  - `final class InMemoryLlmConfigStore implements LlmConfigStore`（测试用）

- [ ] **Step 1: 写失败测试** `test/core/llm/llm_config_store_test.dart`

```dart
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmConfig.effective', () {
    test('内置供应商留空补 preset', () {
      const cfg = LlmConfig(provider: 'deepseek', baseUrl: '', model: '');
      final eff = cfg.effective();
      expect(eff.baseUrl, 'https://api.deepseek.com/v1');
      expect(eff.model, 'deepseek-chat');
      expect(eff.isComplete, isTrue);
    });

    test('custom 缺 baseUrl/model 则 isComplete=false', () {
      const cfg = LlmConfig(provider: 'custom', baseUrl: '', model: 'qwen3:4b');
      expect(cfg.effective().isComplete, isFalse);
    });

    test('baseUrl 末尾斜杠归一化', () {
      const cfg = LlmConfig(
        provider: 'custom',
        baseUrl: 'http://192.168.1.10:11434/v1/',
        model: 'qwen3:4b',
      );
      expect(cfg.effective().baseUrl, 'http://192.168.1.10:11434/v1');
    });
  });

  group('InMemoryLlmConfigStore', () {
    test('read/save/clear 往返；apiKey 留空保持不变', () async {
      final store = InMemoryLlmConfigStore();
      expect(await store.read(), isNull);
      await store.save(const LlmConfig(
          provider: 'custom', baseUrl: 'http://x/v1', model: 'm', apiKey: 'k1'));
      await store.save(const LlmConfig(
          provider: 'custom', baseUrl: 'http://x/v1', model: 'm2')); // apiKey 空=不变
      final cfg = await store.read();
      expect(cfg?.model, 'm2');
      expect(cfg?.apiKey, 'k1');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd eatwise_app && flutter test test/core/llm/llm_config_store_test.dart`
Expected: 编译错误（文件不存在）

- [ ] **Step 3: 实现** `lib/core/llm/llm_config.dart`

```dart
/// 用户自定义 LLM 配置（规格 §3；仅本机存储，D-本-02）。
final class LlmConfig {
  const LlmConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    this.apiKey,
  });

  /// custom / deepseek / qwen / kimi。
  final String provider;
  final String baseUrl;
  final String model;

  /// 鉴权 key（本地 Ollama 等免鉴权端点可空）。
  final String? apiKey;

  /// 内置供应商 preset（与服务端 PROVIDER_PRESETS 对齐；custom 无 preset）。
  static const Map<String, ({String baseUrl, String model})> presets = {
    'deepseek': (baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat'),
    'qwen': (baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus'),
    'kimi': (baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k'),
  };

  /// 生效配置：内置供应商留空补 preset；baseUrl 去末尾斜杠。
  LlmConfig effective() {
    final preset = presets[provider];
    return LlmConfig(
      provider: provider,
      baseUrl: (baseUrl.isEmpty ? preset?.baseUrl ?? '' : baseUrl)
          .replaceAll(RegExp(r'/+$'), ''),
      model: model.isEmpty ? preset?.model ?? '' : model,
      apiKey: apiKey,
    );
  }

  /// 可直接用于直连：baseUrl 与 model 均非空。
  bool get isComplete => baseUrl.isNotEmpty && model.isNotEmpty;
}
```

- [ ] **Step 4: 实现** `lib/core/llm/llm_config_store.dart`

```dart
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LLM 配置本机存储抽象（测试注入内存实现）。
abstract interface class LlmConfigStore {
  /// 未配置返回 null。
  Future<LlmConfig?> read();

  /// 保存；apiKey 为 null/空 = 保持已存 key 不变（控制台密码框语义）。
  Future<void> save(LlmConfig config);

  /// 清除全部配置（回退服务端估算链路）。
  Future<void> clear();
}

/// 本机实现：apiKey → flutter_secure_storage（Keychain/Keystore），
/// 其余 → SharedPreferences（模式同 FoodSeedLoader）。apiKey 禁止写日志。
final class LocalLlmConfigStore implements LlmConfigStore {
  LocalLlmConfigStore({FlutterSecureStorage? secure, required SharedPreferences prefs})
    : _secure = secure ?? const FlutterSecureStorage(),
      _prefs = prefs;

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const String _kProvider = 'llm.provider';
  static const String _kBaseUrl = 'llm.baseUrl';
  static const String _kModel = 'llm.model';
  static const String _kApiKey = 'eatwise.llmApiKey';

  @override
  Future<LlmConfig?> read() async {
    final provider = _prefs.getString(_kProvider);
    if (provider == null) return null;
    return LlmConfig(
      provider: provider,
      baseUrl: _prefs.getString(_kBaseUrl) ?? '',
      model: _prefs.getString(_kModel) ?? '',
      apiKey: await _secure.read(key: _kApiKey),
    );
  }

  @override
  Future<void> save(LlmConfig config) async {
    await _prefs.setString(_kProvider, config.provider);
    await _prefs.setString(_kBaseUrl, config.baseUrl);
    await _prefs.setString(_kModel, config.model);
    if (config.apiKey != null && config.apiKey!.isNotEmpty) {
      await _secure.write(key: _kApiKey, value: config.apiKey);
    }
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_kProvider);
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kModel);
    await _secure.delete(key: _kApiKey);
  }
}

/// 内存实现（widget/单元测试用）。
final class InMemoryLlmConfigStore implements LlmConfigStore {
  LlmConfig? _config;

  @override
  Future<LlmConfig?> read() async => _config;

  @override
  Future<void> save(LlmConfig config) async {
    _config = LlmConfig(
      provider: config.provider,
      baseUrl: config.baseUrl,
      model: config.model,
      apiKey: (config.apiKey == null || config.apiKey!.isEmpty)
          ? _config?.apiKey
          : config.apiKey,
    );
  }

  @override
  Future<void> clear() async => _config = null;
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/llm/llm_config_store_test.dart`
Expected: 4 条全 PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/llm test/core/llm
git commit -m "feat(app): LLM 用户配置实体与本机存储（core/llm）"
```

---

### Task 2: `UserLlmClient` 直连客户端

**Files:**
- Create: `lib/core/llm/user_llm_client.dart`
- Test: `test/core/llm/user_llm_client_test.dart`

**Interfaces:**
- Consumes: Task 1 `LlmConfig`；既有 `FoodEstimate`/`NutritionSnapshot`/`ApiException` 族
- Produces（Task 3 依赖）:
  - `abstract interface class UserEstimateSource { Future<FoodEstimate> estimate(String name, {String? description}); }`（定义在 `user_llm_client.dart`，编排器 import 它）
  - `final class UserLlmClient implements UserEstimateSource { UserLlmClient({Dio? dio, required LlmConfigStore store}); }` —— `estimate` 内部从 store 读配置，`null` 或 `!isComplete` 直接抛不可用；所有失败（超时/不可达/非 2xx/非法 JSON/越界值）一律抛 `BusinessApiException(httpStatus: 503, code: 'ESTIMATE_UNAVAILABLE')`，复用既有 `isEstimateUnavailable` 判定

- [ ] **Step 1: 写失败测试**（dio 注入 `Dio()..httpClientAdapter` 假适配器，或直接用 `dio` 的 `MockAdapter` 模式——项目无 mockito 约定，用自写 `HttpClientAdapter` fake）

```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) => handler(options);
  @override
  void close({bool force = false}) {}
}

Dio _dioWith(Future<ResponseBody> Function(RequestOptions) handler) =>
    Dio()..httpClientAdapter = _FakeAdapter(handler);

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body), status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

const cfg = LlmConfig(provider: 'custom', baseUrl: 'http://192.168.1.10:11434/v1', model: 'qwen3:4b');

Future<InMemoryLlmConfigStore> storeWith(LlmConfig c) async {
  final s = InMemoryLlmConfigStore();
  await s.save(c);
  return s;
}

void main() {
  test('成功：解析 chat/completions 响应', () async {
    final client = UserLlmClient(store: await storeWith(cfg), dio: _dioWith((o) async {
      expect(o.path, 'http://192.168.1.10:11434/v1/chat/completions');
      return _json({'choices': [{'message': {'content': '{"kcal":120,"protein_g":8,"carb_g":15,"fat_g":3,"confidence":"high"}'}}]});
    }));
    final est = await client.estimate('番茄炒蛋');
    expect(est.per100g.kcal, 120);
    expect(est.confidence, 'high');
  });

  test('容忍 ```json 包裹；非法 confidence 按 low', () async {
    final client = UserLlmClient(store: await storeWith(cfg), dio: _dioWith((o) async => _json({'choices': [
      {'message': {'content': '```json\n{"kcal":100,"protein_g":5,"carb_g":10,"fat_g":2,"confidence":"???"}\n```'}}
    ]})));
    final est = await client.estimate('x');
    expect(est.isLowConfidence, isTrue);
  });

  test('字段缺失/越界/非 200/连接失败/未配置 → ESTIMATE_UNAVAILABLE（isEstimateUnavailable 为真）', () async {
    for (final handler in <Future<ResponseBody> Function(RequestOptions)>[
      (o) async => _json({'choices': [{'message': {'content': '{"kcal":100}'}}]}),
      (o) async => _json({'choices': [{'message': {'content': '{"kcal":9999,"protein_g":5,"carb_g":10,"fat_g":2}'}}]}),
      (o) async => _json({}, status: 500),
      (o) async => throw DioException(connectionError: true, requestOptions: o, error: 'refused'),
    ]) {
      final client = UserLlmClient(store: await storeWith(cfg), dio: _dioWith(handler));
      await expectLater(
        client.estimate('x'),
        throwsA(predicate((e) => e is ApiException && isEstimateUnavailable(e))),
      );
    }
    // 未配置：store 为空直接抛，不发请求
    final noCfg = UserLlmClient(store: InMemoryLlmConfigStore(), dio: _dioWith((o) async => throw StateError('不应发请求')));
    await expectLater(noCfg.estimate('x'), throwsA(predicate((e) => e is ApiException && isEstimateUnavailable(e))));
  });
}
```

- [ ] **Step 2: 跑测试确认失败** — `flutter test test/core/llm/user_llm_client_test.dart` → 编译错误

- [ ] **Step 3: 实现** `lib/core/llm/user_llm_client.dart`

```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 营养值合法区间（与服务端 food.rules isPer100gInRange 同口径）。
bool _inRange(NutritionSnapshot p) =>
    p.kcal >= 0 && p.kcal <= 900 &&
    p.proteinG >= 0 && p.proteinG <= 100 &&
    p.carbG >= 0 && p.carbG <= 100 &&
    p.fatG >= 0 && p.fatG <= 100;

/// 与服务端 SYSTEM_PROMPT 逐字一致（openai-compatible.provider.ts）。
const String _systemPrompt =
    '你是中餐营养估算助手。根据用户给出的菜名（可能附带描述），估算每 100g 可食部的营养值。\n'
    '只返回 JSON，不要输出任何其他文字或 Markdown 代码块：\n'
    '{"kcal": number, "protein_g": number, "carb_g": number, "fat_g": number, "confidence": "high"|"medium"|"low"}\n'
    '约束：kcal 0-900，其余 0-100；confidence 表示你对该估算的把握程度。';

/// 用户端估算出口（编排器依赖此窄接口，测试注入 Fake）。
abstract interface class UserEstimateSource {
  Future<FoodEstimate> estimate(String name, {String? description});
}

/// 用户自定义 LLM 直连客户端（规格 §3）：POST {baseUrl}/chat/completions。
/// 不复用 apiDioProvider（其拦截器面向服务端信封/鉴权）；独立裸 Dio。
/// 一切失败抛 503 ESTIMATE_UNAVAILABLE，由编排器决定回落（规格 §6）。
final class UserLlmClient implements UserEstimateSource {
  UserLlmClient({Dio? dio, required LlmConfigStore store})
    : _dio = dio ?? Dio(),
      _store = store;

  final Dio _dio;
  final LlmConfigStore _store;
  static const Duration _timeout = Duration(seconds: 15);

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    final cfg = (await _store.read())?.effective();
    if (cfg == null || !cfg.isComplete) throw _unavailable();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${cfg.baseUrl}/chat/completions',
        options: Options(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: {
            'content-type': 'application/json',
            if (cfg.apiKey != null && cfg.apiKey!.isNotEmpty)
              'authorization': 'Bearer ${cfg.apiKey}',
          },
        ),
        data: {
          'model': cfg.model,
          'temperature': 0.2,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {
              'role': 'user',
              'content': (description != null && description.isNotEmpty)
                  ? '菜名：$name\n描述：$description'
                  : '菜名：$name',
            },
          ],
        },
      );
      final choices = response.data?['choices'];
      final content = (choices is List && choices.isNotEmpty)
          ? (choices.first as Map?)?['message']?['content'] as String?
          : null;
      if (content == null) throw _unavailable();
      return _parse(content);
    } on ApiException {
      rethrow;
    } on Object {
      throw _unavailable();
    }
  }

  /// 容忍 ```json 代码块包裹；字段缺失/非数值/越界一律拒绝。
  FoodEstimate _parse(String content) {
    var text = content.trim();
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      throw _unavailable();
    }
    double? numOf(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }
    final kcal = numOf('kcal'), protein = numOf('protein_g'), carb = numOf('carb_g'), fat = numOf('fat_g');
    if (kcal == null || protein == null || carb == null || fat == null) throw _unavailable();
    final snapshot = NutritionSnapshot(kcal: kcal, proteinG: protein, carbG: carb, fatG: fat);
    if (!_inRange(snapshot)) throw _unavailable();
    const allowed = {'high', 'medium', 'low'};
    final c = raw['confidence'];
    return FoodEstimate(
      per100g: snapshot,
      confidence: c is String && allowed.contains(c) ? c : 'low',
    );
  }

  BusinessApiException _unavailable() => const BusinessApiException(
        httpStatus: 503,
        code: 'ESTIMATE_UNAVAILABLE',
        message: 'estimate unavailable',
      );
}
```

注意：`BusinessApiException` 构造签名以 `lib/core/network/api_exception.dart:36-62` 实际为准（实施时先读该段，按实际命名参数适配）。

- [ ] **Step 4: 跑测试确认通过** — Expected: 4 条全 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/llm/user_llm_client.dart test/core/llm/user_llm_client_test.dart
git commit -m "feat(app): 用户 LLM 直连客户端（OpenAI 兼容，prompt/解析与服务端同口径）"
```

---

### Task 3: 估算编排器（两级回落）+ sheet 接线

**Files:**
- Create: `lib/features/record/custom_food/domain/food_estimate_orchestrator.dart`
- Modify: `lib/features/record/custom_food/presentation/custom_food_providers.dart`（新增 provider）
- Modify: `lib/features/record/custom_food/presentation/custom_food_sheet.dart:148-180`（`_onEstimate` 改走编排器 + fallback toast）
- Modify: `i18n/strings_zh-CN.i18n.json` / `i18n/strings_en.i18n.json`（`record.customFood.estimateFallbackNotice`）
- Test: `test/features/record/custom_food/food_estimate_orchestrator_test.dart`

**Interfaces:**
- Consumes: Task 1 `LlmConfigStore`，Task 2 `UserLlmClient`，既有 `CustomFoodRemote`
- Produces:
  - `final class EstimateOutcome { estimate, usedFallback }`（usedFallback=直连失败落了服务端）
  - `final class FoodEstimateOrchestrator { Future<EstimateOutcome> estimate(String name, {String? description}); }`
  - `final Provider<FoodEstimateOrchestrator> foodEstimateOrchestratorProvider`（测试可 override）

- [ ] **Step 1: 写失败测试**

```dart
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/domain/food_estimate_orchestrator.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = FoodEstimate(
  per100g: NutritionSnapshot(kcal: 100, proteinG: 5, carbG: 10, fatG: 2),
  confidence: 'high',
);

void main() {
  test('未配置 → 直走服务端，usedFallback=false', () async {
    final remote = FakeCustomFoodRemote();
    final orch = FoodEstimateOrchestrator(
      store: InMemoryLlmConfigStore(),
      userClient: _FakeUserClient(ok: true),
      remote: remote,
    );
    final out = await orch.estimate('x');
    expect(out.usedFallback, isFalse);
    expect(remote.estimateCount, 1);
  });

  test('已配置且直连成功 → 不走服务端', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'));
    final remote = FakeCustomFoodRemote();
    final orch = FoodEstimateOrchestrator(store: store, userClient: _FakeUserClient(ok: true), remote: remote);
    final out = await orch.estimate('x');
    expect(out.usedFallback, isFalse);
    expect(remote.estimateCount, 0);
  });

  test('直连失败 → 回落服务端，usedFallback=true', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'));
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: false),
      remote: FakeCustomFoodRemote(),
    );
    final out = await orch.estimate('x');
    expect(out.usedFallback, isTrue);
    expect(out.estimate.per100g.kcal, _sample.per100g.kcal);
  });

  test('双失败 → 抛 ESTIMATE_UNAVAILABLE', () async {
    final store = InMemoryLlmConfigStore();
    await store.save(const LlmConfig(provider: 'custom', baseUrl: 'http://x/v1', model: 'm'));
    final orch = FoodEstimateOrchestrator(
      store: store,
      userClient: _FakeUserClient(ok: false),
      remote: FakeCustomFoodRemote(mode: FakeCustomFoodMode.estimateUnavailable),
    );
    await expectLater(orch.estimate('x'), throwsA(isA<ApiException>()));
  });
}
```

（`_FakeUserClient`：与编排器约定的用户端抽象，见 Step 3。）

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现编排器**。为可测性，编排器依赖一个窄抽象而非 `UserLlmClient` 具体类：

```dart
// lib/features/record/custom_food/domain/food_estimate_orchestrator.dart
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/user_llm_client.dart'; // UserEstimateSource
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';

/// 估算结果 + 是否发生了「直连失败回落服务端」。
final class EstimateOutcome {
  const EstimateOutcome({required this.estimate, required this.usedFallback});
  final FoodEstimate estimate;
  final bool usedFallback;
}

/// 两级回落编排（规格 §2）：已配置 → 直连用户模型；未配置/直连失败 → 服务端。
class FoodEstimateOrchestrator {
  FoodEstimateOrchestrator({
    required LlmConfigStore store,
    required UserEstimateSource userClient,
    required CustomFoodRemote remote,
  })  : _store = store,
        _userClient = userClient,
        _remote = remote;

  final LlmConfigStore _store;
  final UserEstimateSource _userClient;
  final CustomFoodRemote _remote;

  Future<EstimateOutcome> estimate(String name, {String? description}) async {
    final config = (await _store.read())?.effective();
    if (config == null || !config.isComplete) {
      return EstimateOutcome(
        estimate: await _remote.estimate(name, description: description),
        usedFallback: false,
      );
    }
    try {
      return EstimateOutcome(
        estimate: await _userClient.estimate(name, description: description),
        usedFallback: false,
      );
    } on Object {
      return EstimateOutcome(
        estimate: await _remote.estimate(name, description: description),
        usedFallback: true,
      );
    }
  }
}
```

`UserLlmClient`（Task 2）已实现 `UserEstimateSource`，编排器测试注入 `_FakeUserClient implements UserEstimateSource`（`ok:false` 时抛 `BusinessApiException(503, ESTIMATE_UNAVAILABLE)`）。

- [ ] **Step 4: provider 接线**（`custom_food_providers.dart` 追加）

```dart
final Provider<LlmConfigStore> llmConfigStoreProvider = Provider<LlmConfigStore>(
  (ref) => throw UnimplementedError('override in main'), // main.dart 用 SharedPreferences 实例 override
);

final Provider<FoodEstimateOrchestrator> foodEstimateOrchestratorProvider =
    Provider<FoodEstimateOrchestrator>((ref) {
  final store = ref.watch(llmConfigStoreProvider);
  return FoodEstimateOrchestrator(
    store: store,
    userClient: UserLlmClient(store: store),
    remote: ref.watch(customFoodRemoteProvider),
  );
});
```

`main.dart` 中找既有 `SharedPreferences` override 点（`food_seed_loader` 已用 prefs，main 必有实例），同处 override `llmConfigStoreProvider` 为 `LocalLlmConfigStore(prefs: prefs)`；`InMemoryTokenStore` 等测试 override 同法。实施时先 grep `sharedPreferencesProvider` 或 `SharedPreferences.getInstance` 定位。

- [ ] **Step 5: i18n 新增**（两个文件 `record.customFood` 段各加一行）

- zh-CN：`"estimateFallbackNotice": "你的模型连接失败，已改用云端估算"`
- en：`"estimateFallbackNotice": "Your model couldn't be reached — used the cloud estimate instead"`

Run: `dart run slang`

- [ ] **Step 6: sheet 接线**（`custom_food_sheet.dart` `_onEstimate`）

```dart
final outcome = await ref.read(foodEstimateOrchestratorProvider).estimate(name);
if (!mounted) return;
final estimate = outcome.estimate;
if (outcome.usedFallback) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(cs.estimateFallbackNotice)),
  );
}
setState(() { /* 预填四营养，同现状 */ });
```

`custom_food_strings.dart` 同步加 `estimateFallbackNotice` getter。异常分支逻辑不变（`isEstimateUnavailable` 降级）。

- [ ] **Step 7: 跑测试**

Run: `flutter test test/features/record/custom_food/`
Expected: 编排器 4 条 + 既有 custom_food 测试全 PASS（sheet 测试若 override 了 `customFoodRemoteProvider` 需补 override `foodEstimateOrchestratorProvider`——实施者检查 `custom_food_sheet_test.dart` 并适配）

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(app): 估算两级回落编排器（用户模型直连 → 服务端）+ sheet 接线"
```

---

### Task 4: 设置页「AI 模型」配置

**Files:**
- Create: `lib/features/settings/presentation/ai_model_settings_page.dart`
- Modify: `lib/features/settings/presentation/settings_page.dart`（偏好组加入口行）
- Modify: `lib/app/router/app_router.dart`（`/settings/ai-model` 路由）
- Modify: `i18n/strings_zh-CN.i18n.json` / `i18n/strings_en.i18n.json`（`settings.aiModel.*`）
- Test: `test/features/settings/ai_model_settings_page_test.dart`

**Interfaces:**
- Consumes: Task 1 store、Task 2 `UserLlmClient`（测试连接）、Task 3 `llmConfigStoreProvider`
- Produces: `AiModelSettingsPage`（路由 `/settings/ai-model`）；i18n keys `settings.aiModel.{title,provider,baseUrl,model,apiKey,apiKeyHint,save,test,testing,testOk,testFail,clear,saved,cleared}`

- [ ] **Step 1: i18n keys**（zh-CN / en 双语）后 `dart run slang`

- [ ] **Step 2: 写失败 widget 测试**（`ProviderScope` override `llmConfigStoreProvider` 为 `InMemoryLlmConfigStore`；覆盖：初始回填已存配置、保存写 store、apiKey 留空保持、清除配置、测试连接按钮禁用态/loading 态）——参照既有 `test/features/settings/settings_page_test.dart` 的装配方式

- [ ] **Step 3: 跑测试确认失败**

- [ ] **Step 4: 实现页面**

要点（非完整代码，实施者按设计稿 token 与 `_SettingsTile` 风格实现）：
- `ConsumerStatefulWidget`，`initState` 读 store 回填四个 `TextEditingController`
- provider `DropdownButton`：custom/deepseek/qwen/kimi；选内置供应商时 baseUrl/model 输入框 hint 显示 preset 值、可留空
- apiKey 用 `obscureText`；hint「留空保持不变」
- 「保存」：`store.save(LlmConfig(...))` → snackbar `saved`；provider 非空、custom 时 baseUrl/model 必填校验
- 「测试连接」：读当前表单构成 config（未保存也可测），`GET {effective.baseUrl}/models`（dio，10s 超时，带 Bearer）→ 200 显示 `testOk`，否则 `testFail` + 原因；进行中按钮 loading 防连点
- 「清除配置」：确认后 `store.clear()` → snackbar `cleared`
- 样式 token：`AppColors/AppSpacing/AppTextStyles/AppRadii`；行触控 ≥44px

- [ ] **Step 5: 入口与路由**

`settings_page.dart` 偏好组加一行 `_SettingsTile`（标题 `t.settings.aiModel.title`，tap → `context.push('/settings/ai-model')`）；`app_router.dart` 在 `/profile` 同层加 `GoRoute(path: '/settings/ai-model', builder: (_, __) => const AiModelSettingsPage())`。

- [ ] **Step 6: 跑测试确认通过** + `flutter test test/features/settings/` 既有测试不回归

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(app): 设置页 AI 模型配置（provider/baseUrl/model/apiKey + 测试连接）"
```

---

### Task 5: iOS ATS 放行局域网 + 全门禁

**Files:**
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Info.plist 加 ATS 局域网例外**（顶层 dict 内）

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

- [ ] **Step 2: iOS 构建验证**

Run: `flutter build ios --debug --no-codesign`
Expected: 构建成功（需本机 CocoaPods 环境；环境缺失则记录原因，不阻塞合并，CI build-ios 兜底）

- [ ] **Step 3: 全门禁**

Run: `dart format . && dart analyze && flutter test`
Expected: format 无 diff、analyze 零 issue、全部测试 PASS

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Info.plist
git commit -m "feat(app): iOS ATS 放行局域网 http（NSAllowsLocalNetworking，用户 LLM 直连）"
```

---

## Self-Review 记录

- 规格 §2 数据流 → Task 3；§3 模块 → Task 1/2；§4 设置页 → Task 4；§5 原生 → Task 5；§6 错误矩阵 → Task 2 测试 + Task 3 编排；§7 测试 → 各 Task 内嵌；§8 YAGNI 无对应 Task（正确）
- 类型一致性：`LlmConfig.effective()`、`isComplete`、`EstimateOutcome.usedFallback`、`UserEstimateSource`（定义于 `user_llm_client.dart`，编排器与测试 import）在 Task 2/3/4 间签名一致
- 已知风险：`BusinessApiException` 构造参数以 `api_exception.dart` 实际为准；sheet 既有测试的 provider override 需适配（Task 3 Step 7 已标注）
