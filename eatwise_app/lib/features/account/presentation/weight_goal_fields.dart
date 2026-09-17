import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/weight_loss_plan.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 减重目标字段组（阶段 B：onboarding 目标页与「我的-身体档案」共用控件）。
///
/// 目标体重 + 目标日期（快捷 4/8/12 周 + 自定义日期）；均可留空/清空，
/// 非空体重做取值域校验（25–300，[isValidWeightKg]），非法输入通过
/// [onChanged] 上报 isValid=false 由父级禁用提交。
class WeightGoalFields extends StatefulWidget {
  const WeightGoalFields({
    super.key,
    required this.today,
    required this.onChanged,
    this.initialWeightKg,
    this.initialDate,
  });

  /// 计算基准日（快捷周数与日期 picker 的下界；测试注入固定时钟）。
  final LocalDate today;

  /// 初始目标体重（kg）。
  final double? initialWeightKg;

  /// 初始目标日期。
  final LocalDate? initialDate;

  /// 取值变化回调（weightKg/date 均可空 = 清空；isValid 为整体可提交性）。
  final void Function(double? weightKg, LocalDate? date, bool isValid)
  onChanged;

  @override
  State<WeightGoalFields> createState() => _WeightGoalFieldsState();
}

class _WeightGoalFieldsState extends State<WeightGoalFields> {
  late final TextEditingController _weightController;
  late LocalDate? _date = widget.initialDate;

  /// 目标日期取值域：明天 ~ 2 年内（与服务端 DTO 校验同口径）。
  DateTime get _firstDate =>
      DateTime.utc(widget.today.year, widget.today.month, widget.today.day + 1);

  DateTime get _lastDate =>
      DateTime.utc(widget.today.year + 2, widget.today.month, widget.today.day);

  @override
  void initState() {
    super.initState();
    final w = widget.initialWeightKg;
    _weightController = TextEditingController(
      text: w == null
          ? ''
          : (w == w.roundToDouble() ? w.toInt().toString() : '$w'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  double? get _weightKg {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _weightError(Translations t) {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    final kg = double.tryParse(raw);
    if (kg == null || !isValidWeightKg(kg)) {
      return t.onboarding.goal.targetWeightInvalid;
    }
    return null;
  }

  void _emit() {
    final t = Translations.of(context);
    widget.onChanged(_weightKg, _date, _weightError(t) == null);
  }

  void _setDate(LocalDate? date) {
    setState(() => _date = date);
    _emit();
  }

  Future<void> _pickDate() async {
    final t = Translations.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null
          ? _firstDate
          : DateTime.utc(_date!.year, _date!.month, _date!.day),
      firstDate: _firstDate,
      lastDate: _lastDate,
      // 自定义日期受服务端 ≤2 年约束（picker 下界为本地明天）。
      helpText: t.onboarding.goal.customDate,
      confirmText: t.common.action.confirm,
      cancelText: t.common.action.cancel,
    );
    if (picked != null) {
      _setDate(LocalDate(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.onboarding.goal.targetWeightLabel,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s1),
        TextField(
          key: const ValueKey<String>('goal.targetWeight'),
          controller: _weightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            // 仅数字与小数点（负数/字母从源头拦截）。
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          onChanged: (_) {
            setState(() {}); // 触发错误文案刷新
            _emit();
          },
          style: textStyles.textBase,
          decoration: InputDecoration(
            hintText: t.onboarding.goal.targetWeightHint,
            errorText: _weightError(t),
            filled: true,
            fillColor: colors.bgSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          t.onboarding.goal.targetDateLabel,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: <Widget>[
            for (final weeks in const <int>[4, 8, 12])
              ChoiceChip(
                key: ValueKey<String>('goal.quickWeeks.$weeks'),
                label: Text(t.onboarding.goal.quickWeeks(weeks: weeks)),
                selected:
                    _date != null &&
                    daysBetweenLocalDate(widget.today, _date!) == weeks * 7,
                onSelected: (_) => _setDate(widget.today.addDays(weeks * 7)),
              ),
            ActionChip(
              key: const ValueKey<String>('goal.customDate'),
              label: Text(t.onboarding.goal.customDate),
              onPressed: _pickDate,
            ),
            if (_date != null)
              ActionChip(
                key: const ValueKey<String>('goal.clearDate'),
                avatar: const Icon(Icons.close, size: 16),
                label: Text(t.onboarding.goal.clearDate),
                onPressed: () => _setDate(null),
              ),
          ],
        ),
        if (_date != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Text(
            formatLocalDate(context, _date!),
            key: const ValueKey<String>('goal.datePreview'),
            style: textStyles.textSm.copyWith(color: colors.brandPrimary),
          ),
        ],
      ],
    );
  }
}

/// 本地日期展示格式化（zh-CN：2026年12月1日；其他：ISO yyyy-MM-dd）。
String formatLocalDate(BuildContext context, LocalDate date) {
  final locale = Localizations.localeOf(context).languageCode;
  if (locale == 'zh') return '${date.year}年${date.month}月${date.day}日';
  return date.toIsoString();
}
