import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/settings/presentation/ondevice_model_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 连接测试窄接口（widget 测试注入 Fake；模式同 FakeCustomFoodRemote）。
/// 成功返回 null；失败返回可读原因（HTTP 状态码 / 错误类型）。
abstract interface class LlmConnectionTester {
  Future<String?> test(LlmConfig config);
}

/// 生产实现：独立裸 Dio（不复用 apiDioProvider，其拦截器面向服务端
/// 信封/鉴权），GET {baseUrl}/models，10s 超时，有 apiKey 带 Bearer。
final class DioLlmConnectionTester implements LlmConnectionTester {
  DioLlmConnectionTester({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<String?> test(LlmConfig config) async {
    try {
      await _dio.get<void>(
        '${config.baseUrl}/models',
        options: Options(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: <String, String>{
            if (config.apiKey != null && config.apiKey!.isNotEmpty)
              'authorization': 'Bearer ${config.apiKey}',
          },
        ),
      );
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return status != null ? 'HTTP $status' : e.type.name;
    }
  }
}

/// 测试连接出口（测试 override 为 Fake）。
final Provider<LlmConnectionTester> llmConnectionTesterProvider =
    Provider<LlmConnectionTester>((ref) => DioLlmConnectionTester());

/// 测试连接失败原因 → 友好文案（Y1：dio 内部错误类型名如
/// connectionError 不上屏；HTTP 状态码保留，401/403 单列鉴权失败）。
String llmTestFailText(Translations t, String reason) {
  final m = t.settings.aiModel;
  if (reason.startsWith('HTTP ')) {
    final status = int.tryParse(reason.substring(5));
    if (status == 401 || status == 403) return m.testFailAuth;
    return m.testFail(reason: reason);
  }
  return switch (reason) {
    'connectionTimeout' ||
    'sendTimeout' ||
    'receiveTimeout' => m.testFailTimeout,
    _ => m.testFailNetwork,
  };
}

/// AI 模型配置页（/settings/ai-model）：用户自定义 LLM 的
/// provider/baseUrl/model/apiKey 本机配置（规格 §3，D-本-02）。
/// 内置供应商（deepseek/qwen/kimi）留空即补 preset；apiKey 留空保持不变；
/// 测试连接用当前表单（未保存也可测）；清除后回退服务端估算链路。
class AiModelSettingsPage extends ConsumerStatefulWidget {
  const AiModelSettingsPage({super.key});

  @override
  ConsumerState<AiModelSettingsPage> createState() =>
      _AiModelSettingsPageState();
}

class _AiModelSettingsPageState extends ConsumerState<AiModelSettingsPage> {
  static const List<String> _providers = <String>[
    'custom',
    'deepseek',
    'qwen',
    'kimi',
  ];

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  String _provider = 'custom';

  /// 已存配置（apiKey 留空测试时回退用）。
  LlmConfig? _stored;

  bool _testing = false;
  bool _baseUrlInvalid = false;
  bool _modelInvalid = false;

  @override
  void initState() {
    super.initState();
    // 表单变化联动测试按钮可用态与 preset hint。
    _baseUrlController.addListener(_onFormChanged);
    _modelController.addListener(_onFormChanged);
    _apiKeyController.addListener(_onFormChanged);
    unawaited(_load());
  }

  void _onFormChanged() => setState(() {});

  Future<void> _load() async {
    final config = await ref.read(llmConfigStoreProvider).read();
    if (!mounted || config == null) return;
    setState(() {
      _stored = config;
      if (_providers.contains(config.provider)) _provider = config.provider;
      _baseUrlController.text = config.baseUrl;
      _modelController.text = config.model;
      _apiKeyController.text = config.apiKey ?? '';
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 当前表单构成的生效配置（未保存也可测）：内置供应商留空补 preset；
  /// apiKey 留空回退已存 key（与「留空保持不变」语义一致）。
  LlmConfig _formConfig() {
    final apiKeyText = _apiKeyController.text.trim();
    return LlmConfig(
      provider: _provider,
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: apiKeyText.isNotEmpty ? apiKeyText : _stored?.apiKey,
    ).effective();
  }

  String _providerLabel(Translations t, String provider) => switch (provider) {
    'deepseek' => t.settings.aiModel.providers.deepseek,
    'qwen' => t.settings.aiModel.providers.qwen,
    'kimi' => t.settings.aiModel.providers.kimi,
    _ => t.settings.aiModel.providers.custom,
  };

  Future<void> _save() async {
    final t = Translations.of(context);
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    // 校验：provider 非空（下拉恒有值）；custom 时 baseUrl/model 必填。
    final baseUrlMissing = _provider == 'custom' && baseUrl.isEmpty;
    final modelMissing = _provider == 'custom' && model.isEmpty;
    if (baseUrlMissing || modelMissing) {
      setState(() {
        _baseUrlInvalid = baseUrlMissing;
        _modelInvalid = modelMissing;
      });
      return;
    }
    setState(() {
      _baseUrlInvalid = false;
      _modelInvalid = false;
    });
    final apiKeyText = _apiKeyController.text.trim();
    final store = ref.read(llmConfigStoreProvider);
    await store.save(
      LlmConfig(
        provider: _provider,
        baseUrl: baseUrl,
        model: model,
        // apiKey 留空 = null → store 保持已存 key 不变（控制台密码框语义）。
        apiKey: apiKeyText.isEmpty ? null : apiKeyText,
      ),
    );
    _stored = await store.read();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.settings.aiModel.saved)));
  }

  Future<void> _test() async {
    final t = Translations.of(context);
    final config = _formConfig();
    setState(() => _testing = true);
    final reason = await ref.read(llmConnectionTesterProvider).test(config);
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reason == null
              ? t.settings.aiModel.testOk
              : llmTestFailText(t, reason),
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.aiModel.clearConfirmTitle),
        content: Text(t.settings.aiModel.clearConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: colors.signalRed),
            child: Text(t.settings.aiModel.clearConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(llmConfigStoreProvider).clear();
    if (!mounted) return;
    setState(() {
      _stored = null;
      _provider = 'custom';
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _baseUrlInvalid = false;
      _modelInvalid = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.settings.aiModel.cleared)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final preset = LlmConfig.presets[_provider];
    final canTest = !_testing && _formConfig().isComplete;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.settings.aiModel.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            // 端侧小模型（下载/开关）；下方为用户自定义 API 配置。
            const OnDeviceModelCard(),
            const SizedBox(height: AppSpacing.s4),
            Container(
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                borderRadius: radii.rLg,
              ),
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: InputDecoration(
                      labelText: t.settings.aiModel.provider,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final provider in _providers)
                        DropdownMenuItem<String>(
                          value: provider,
                          child: Text(_providerLabel(t, provider)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _provider = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  TextField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t.settings.aiModel.baseUrl,
                      // 内置供应商：hint 显示 preset 值，可留空。
                      hintText: preset?.baseUrl,
                      errorText: _baseUrlInvalid
                          ? t.settings.aiModel.baseUrlRequired
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  TextField(
                    controller: _modelController,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t.settings.aiModel.model,
                      hintText: preset?.model,
                      errorText: _modelInvalid
                          ? t.settings.aiModel.modelRequired
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t.settings.aiModel.apiKey,
                      hintText: t.settings.aiModel.apiKeyHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _save,
              child: Text(t.settings.aiModel.save),
            ),
            const SizedBox(height: AppSpacing.s3),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              // config 不完整或进行中禁用（防连点）。
              onPressed: canTest ? _test : null,
              child: _testing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Text(t.settings.aiModel.testing),
                      ],
                    )
                  : Text(t.settings.aiModel.test),
            ),
            const SizedBox(height: AppSpacing.s4),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.signalRed,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _clear,
              child: Text(t.settings.aiModel.clear),
            ),
          ],
        ),
      ),
    );
  }
}
