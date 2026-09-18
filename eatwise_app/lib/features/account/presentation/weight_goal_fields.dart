import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/application/weight_unit_controller.dart';
import 'package:eatwise/features/account/domain/weight_unit.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/weight_loss_plan.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 减重目标字段组（阶段 B：onboarding 目标页与「我的-身体档案」共用控件）。
///
/// 目标体重 + 目标日期（快捷 4/8/12 周 + 自定义日期）；均可留空/清空，
/// 非空体重做取值域校验（25–300 kg，[isValidWeightKg]），非法输入通过
/// [onChanged] 上报 isValid=false 由父级禁用提交。
///
/// 目标体重与身体档案/记录弹窗同款「公斤/斤」切换（共用 weightUnitProvider
/// 偏好）——存储与校验一律 kg（斤 ÷2）。
class WeightGoalFields extends ConsumerStatefulWidget {
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
  ConsumerState<WeightGoalFields> createState() => _WeightGoalFieldsState();
}

class _WeightGoalFieldsState extends ConsumerState<WeightGoalFields> {
  late WeightUnit _unit;
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
    _unit = ref.read(weightUnitProvider);
    // 存储值一律 kg：选斤时预填换算后的斤数（1 位小数）。
    final w = widget.initialWeightKg;
    _weightController = TextEditingController(
      text: w == null ? '' : formatWeightForUnit(w, _unit),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  /// 当前输入换算为存储单位 kg（选斤时 ÷2；非法/留空返回 null）。
  double? get _weightKg {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) return null;
    return _unit == WeightUnit.jin ? jinToKg(value) : value;
  }

  String? _weightError(Translations t) {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    // 校验按存储单位 kg（25–300）：斤输入先换算再判定。
    final kg = _weightKg;
    if (kg == null || !isValidWeightKg(kg)) {
      return _unit == WeightUnit.jin
          ? t.onboarding.goal.targetWeightInvalidJin
          : t.onboarding.goal.targetWeightInvalid;
    }
    return null;
  }

  /// 切换公斤/斤：写偏好（weightUnitProvider 为单一事实源，本控件与同页
  /// 其他体重输入经 listen 同步换算，三处输入共用）。
  void _onUnitChanged(WeightUnit unit) {
    if (unit == _unit) return;
    ref.read(weightUnitProvider.notifier).setUnit(unit);
  }

  /// 应用新单位：已输入的数值按旧单位换算成 kg 后以新单位重填
  /// （非法输入保留原文，交由校验提示）。
  void _applyUnit(WeightUnit unit) {
    if (unit == _unit) return;
    // 输入值按旧单位解释：旧单位是斤则先 ÷2 回到 kg，再以新单位重填。
    final parsed = double.tryParse(_weightController.text.trim());
    final kg = parsed == null
        ? null
        : (_unit == WeightUnit.jin ? jinToKg(parsed) : parsed);
    setState(() => _unit = unit);
    if (kg != null) {
      _weightController.text = formatWeightForUnit(kg, unit);
    }
    _emit();
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
    // 单位偏好为单一事实源：同页其他体重输入切换时此处同步换算。
    ref.listen<WeightUnit>(
      weightUnitProvider,
      (prev, next) => _applyUnit(next),
    );
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _unit == WeightUnit.jin
                    ? t.onboarding.goal.targetWeightLabelJin
                    : t.onboarding.goal.targetWeightLabel,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ),
            SegmentedButton<WeightUnit>(
              key: const ValueKey<String>('goal.weightUnit'),
              segments: <ButtonSegment<WeightUnit>>[
                ButtonSegment<WeightUnit>(
                  value: WeightUnit.kg,
                  label: Text(t.onboarding.profile.weightUnitKg),
                ),
                ButtonSegment<WeightUnit>(
                  value: WeightUnit.jin,
                  label: Text(t.onboarding.profile.weightUnitJin),
                ),
              ],
              selected: <WeightUnit>{_unit},
              onSelectionChanged: (selection) =>
                  _onUnitChanged(selection.first),
            ),
          ],
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
            hintText: _unit == WeightUnit.jin
                ? t.onboarding.goal.targetWeightHintJin
                : t.onboarding.goal.targetWeightHint,
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
