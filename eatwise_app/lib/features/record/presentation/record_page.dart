import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/scroll_depth_tracker.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_flow.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_strings.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/food_detail_sheet.dart';
import 'package:eatwise/features/record/presentation/light_record_section.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/presentation/frequent_flow.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_flow.dart';
import 'package:eatwise/features/record/recognition/presentation/voice_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M3 记录页（PRD M3：四入口 + 双语搜索 + 份量编辑 + 乐观更新 +
/// D-11 撤销吐司 + D-20「待同步 N 条」入口）。
///
/// 入口已接通：拍照识别（D-16 远端 stub + 手动搜索兜底）、
/// 语音录入（系统 ASR + 自研解析）、常吃复用（本地高频聚合）、
/// 扫码记（OFF 条码代理，未收录降级手动搜索/自定义食物）。
/// 不注册路由，由主代理统一集成到 Tab 结构。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  /// 搜索框焦点（识别降级对话框「手动搜索」出口对焦用）。
  final FocusNode _searchFocusNode = FocusNode();

  /// 埋点服务（dispose 阶段不可再用 ref，提前持有）。
  late final AnalyticsService _analytics = ref.read(analyticsServiceProvider);

  /// 当前记录流程 ID（§2.5 耗时事件对关联键；进入记录页即开启，
  /// 每次确认成功后重启下一条流程）。
  String? _flowId;

  /// 有效交互步数（≤3 步口径 §2.5：入口点击/选中食物/确认，不含曝光）。
  int _stepCount = 0;

  /// 上次确认入账时刻（`record_undo_click.after_ms`）。
  int? _lastConfirmMs;

  @override
  void initState() {
    super.initState();
    // 搜索框清空键显隐跟随文本（含程序化 clear）。
    _searchController.addListener(() => setState(() {}));
    // 记录流程起点（§3.3 record_flow_start：进入记录页即触发一次）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flowId ??= _analytics.startRecordFlow();
    });
  }

  @override
  void dispose() {
    // 流程开始但未确认即退出 → record_flow_abandon（§3.3，reason=exit）。
    final flowId = _flowId;
    if (flowId != null) {
      _analytics.track(
        'record_flow_abandon',
        properties: <String, Object?>{
          'flow_id': flowId,
          'reason': 'exit',
          'elapsed_ms': _analytics.recordFlowElapsedMs(flowId) ?? 0,
        },
      );
      _analytics.endRecordFlow(flowId);
    }
    _searchController.dispose();
    _amountController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 阶段 E：搜索结果点击 → 食物详情弹层（热量/供能圆环/红绿灯/明细折叠）；
  /// 弹层内确认份量后回填既有选中态并走 `_confirm` 原链路入账
  /// （乐观更新 + D-11 撤销吐司 + 流程埋点不变）。
  void _openFoodDetail(Food food) {
    _stepCount++;
    unawaited(
      showFoodDetailSheet(
        context: context,
        food: food,
        onConfirm: (amountText) {
          ref.read(recordSelectedFoodProvider.notifier).state = food;
          // 份量必填：不再默认填 100g，留空由用户输入
          // （避免「没写克数也能提交」的误导性默认值）。
          ref.read(recordAmountTextProvider.notifier).state = amountText;
          ref.read(recordEntrySourceProvider.notifier).state =
              EntrySource.manual;
          ref.read(recordLowConfidenceProvider.notifier).state = false;
          unawaited(_confirm(RecordStrings.of(context)));
        },
      ),
    );
  }

  /// 三入口点击（§3.3 record_entry_click；更新 flow 最终入口）。
  void _onEntryTap(String entryType, VoidCallback start) {
    _stepCount++;
    final flowId = _flowId;
    if (flowId != null) {
      _analytics.updateRecordFlowEntry(flowId, entryType);
      _analytics.track(
        'record_entry_click',
        properties: <String, Object?>{
          'entry_type': entryType,
          'flow_id': flowId,
        },
      );
    }
    start();
  }

  /// 一键确认：乐观更新入账（UI 立即经流展示）+「已记录·撤销」吐司（D-11）。
  Future<void> _confirm(RecordStrings s) async {
    if (_confirming) return; // 防连点重复入账
    _confirming = true;
    try {
      await _doConfirm(s);
    } finally {
      _confirming = false;
    }
  }

  bool _confirming = false;

  Future<void> _doConfirm(RecordStrings s) async {
    final food = ref.read(recordSelectedFoodProvider);
    if (food == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final amount = double.tryParse(ref.read(recordAmountTextProvider));
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(s.amountInvalid)));
      return;
    }
    _stepCount++;
    final repo = ref.read(recordRepositoryProvider);
    final entrySource = ref.read(recordEntrySourceProvider);
    final isEdited = ref.read(recordAmountTextProvider) != '100';
    final entry = await repo.addEntry(
      RecordDraft(
        foodId: food.id,
        amountG: amount,
        mealUtc: DateTime.now().toUtc(),
        source: entrySource,
        // 阶段 C：断食计时进行中的用餐打「断食期用餐」本地标记（不上行）。
        duringFast: ref.read(isFastingInProgressProvider),
      ),
    );
    // 确认记录成功（§3.3 record_flow_success，核心事件 §1.5 立即上报；
    // 健康明细不上报，仅枚举与计数 §1.6-3）。
    final flowId = _flowId;
    final flow = flowId == null ? null : _analytics.endRecordFlow(flowId);
    _flowId = null;
    _lastConfirmMs = DateTime.now().millisecondsSinceEpoch;
    if (flowId != null) {
      _analytics.track(
        'record_flow_success',
        properties: <String, Object?>{
          'flow_id': flowId,
          'duration_ms': flow?.durationMs ?? 0,
          'step_count': _stepCount,
          'entry_type': flow?.entryType ?? _entryEventType(entrySource),
          'item_count': 1,
          'record_kind': 'food',
          'is_edited': isEdited,
          'meal_period': _mealPeriod(),
          // 断食期用餐标记（阶段 C，布尔枚举非健康明细）。
          'during_fast': entry.duringFast,
          // D-20 四态：乐观更新入账即 pending。
          'sync_state': 'pending',
        },
        flushNow: true,
      );
    }
    // 连续入账：确认成功即开启下一条流程并重置步数（§3.3 一单一
    // flow_id；不重启会让第二单起 record_entry_click/success 全部丢失）。
    _flowId = _analytics.startRecordFlow();
    _stepCount = 0;
    if (!mounted) return;
    // 提交成功后收起键盘（Y5），避免遮挡 toast 与底部内容。
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(recordSelectedFoodProvider.notifier).state = null;
    ref.read(recordSearchQueryProvider.notifier).state = '';
    ref.read(recordEntrySourceProvider.notifier).state = EntrySource.manual;
    ref.read(recordLowConfidenceProvider.notifier).state = false;
    _searchController.clear();
    // 连续入账：新吐司顶替旧的（不排队），与饮水流一致（D-11）。
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.toastRecorded),
        duration: repo.undoWindow,
        // D-11 撤销窗 10 秒：Flutter ≥3.44 带 action 的 SnackBar 默认
        // persist=true（不自动消失），必须显式置 false。
        persist: false,
        action: SnackBarAction(
          label: s.toastUndo,
          onPressed: () => unawaited(_undo(repo, entry.localId, s)),
        ),
      ),
    );
  }

  /// D-11 撤销：撤回该条（乐观更新回滚）。
  Future<void> _undo(
    RecordRepository repo,
    String localId,
    RecordStrings s,
  ) async {
    final ok = await repo.undo(localId);
    if (ok) {
      // 撤销埋点（§3.3 record_undo_click；ID 哈希仅用于事件配对 §1.6-4）。
      _analytics.track(
        'record_undo_click',
        properties: <String, Object?>{
          'record_id_hash': anonymizedContentId(localId),
          'after_ms': _lastConfirmMs == null
              ? 0
              : DateTime.now().millisecondsSinceEpoch - _lastConfirmMs!,
        },
      );
    }
    if (ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.toastUndone)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 三入口（拍照/语音/常吃）填充份量时同步进输入框。
    ref.listen<String>(recordAmountTextProvider, (previous, next) {
      if (_amountController.text != next) _amountController.text = next;
    });
    // 识别降级对话框「手动搜索」出口：预填识别名（如有）+ 对焦搜索框。
    ref.listen<String?>(recordSearchPrefillProvider, (previous, next) {
      if (next == null) return;
      ref.read(recordSearchPrefillProvider.notifier).state = null;
      if (next.isNotEmpty) {
        _searchController.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        ref.read(recordSearchQueryProvider.notifier).state = next;
      }
      _searchFocusNode.requestFocus();
    });
    final s = RecordStrings.of(context);
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final pendingCount = ref.watch(recordPendingCountProvider).value ?? 0;
    final today = ref.watch(recordTodayNutritionProvider).value;
    final selected = ref.watch(recordSelectedFoodProvider);
    final results = ref.watch(recordFoodSearchProvider);
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    // 键盘可见性须在 Scaffold 之外读取（resizeToAvoidBottomInset 会把
    // bottom inset 从 body 的 MediaQuery 里消化掉）。
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(s.pageTitle, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 高度受限（小屏 / 键盘弹起 / 结果卡展开）时隐藏饮水·体重轻量区，
            // 保证记录主流程（搜索 → 结果卡 → 确认）不溢出（〔假设〕阈值 560）。
            final showLightSection = constraints.maxHeight >= 560;
            return Column(
              children: <Widget>[
                // 「待同步 N 条」可见入口（§4.1：>0 时展示，点击进同步详情页
                // ——详情页由主代理集成，当前占位提示）。
                if (pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s2,
                      AppSpacing.s4,
                      0,
                    ),
                    child: Semantics(
                      button: true,
                      label: s.pendingBanner(pendingCount),
                      child: Material(
                        color: colors.bgSecondary,
                        borderRadius: radii.rMd,
                        child: InkWell(
                          borderRadius: radii.rMd,
                          onTap: () => ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(s.comingSoon))),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s4,
                              vertical: AppSpacing.s3,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  color: colors.brandAccent,
                                ),
                                const SizedBox(width: AppSpacing.s2),
                                Expanded(
                                  child: Text(
                                    s.pendingBanner(pendingCount),
                                    style: textStyles.textSm.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // 四入口（D-16 + 扫码扩充）：拍照识别 / 语音录入 / 常吃复用 / 扫码记。
                // 入口标签 2–3 字，同排四卡（Expanded 均分）在 ≥320px 宽屏不拥挤，
                // 故不放搜索框右侧图标（与三入口同排样式，层级一致）。
                // 薄荷走查 P2：拍照记为最高频 AI 入口，主色描边 + 浅主色底
                // 提升视觉权重，其余三格保持原样。
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  child: Row(
                    children: <Widget>[
                      _EntryCard(
                        icon: Icons.photo_camera_outlined,
                        label: s.entryPhoto,
                        highlighted: true,
                        onTap: () => _onEntryTap(
                          'camera',
                          () => unawaited(startPhotoRecognition(context, ref)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      _EntryCard(
                        icon: Icons.mic_none_outlined,
                        label: s.entryVoice,
                        onTap: () => _onEntryTap(
                          'voice',
                          () => unawaited(startVoiceInput(context, ref)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      _EntryCard(
                        icon: Icons.favorite_border_outlined,
                        label: s.entryFrequent,
                        onTap: () => _onEntryTap(
                          'frequent',
                          () => unawaited(startFrequentPick(context)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      _EntryCard(
                        icon: Icons.qr_code_scanner_outlined,
                        label: BarcodeStrings.of(context).entry,
                        onTap: () => _onEntryTap(
                          'barcode',
                          () => unawaited(startBarcodeScan(context, ref)),
                        ),
                      ),
                    ],
                  ),
                ),
                // 饮水 / 体重轻量记录区（PRD M3 功能点 4；空间不足时让位主流程）。
                if (showLightSection) const LightRecordSection(),
                // 食物搜索（双语匹配，D-15/D-16）。
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: textStyles.textBase,
                    decoration: InputDecoration(
                      hintText: s.searchHint,
                      prefixIcon: const Icon(Icons.search),
                      // 一键清空（走查 B-4）：输入非空时出现。
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: s.searchClear,
                              onPressed: () {
                                _searchController.clear();
                                ref
                                        .read(
                                          recordSearchQueryProvider.notifier,
                                        )
                                        .state =
                                    '';
                              },
                            ),
                      filled: true,
                      fillColor: colors.bgSecondary,
                      border: OutlineInputBorder(
                        borderRadius: radii.rMd,
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) =>
                        ref.read(recordSearchQueryProvider.notifier).state =
                            value,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                // 搜索结果列表。
                Expanded(
                  child: results.when(
                    data: (foods) {
                      if (foods.isEmpty) {
                        // 空态可滚动（走查 Y1）：键盘顶起高度不足时
                        // 可滚而不溢出（BOTTOM OVERFLOWED）。
                        return LayoutBuilder(
                          builder: (context, box) => SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: box.maxHeight,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    // 空态三件套（薄荷走查 P2）：图标 + 引导
                                    // 文案 + 自定义食物 CTA。
                                    Icon(
                                      Icons.search_off_outlined,
                                      size: 40,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(height: AppSpacing.s2),
                                    Text(
                                      s.searchEmpty,
                                      style: textStyles.textSm.copyWith(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.s2),
                                    // K2 自定义食物入口（搜索无结果 CTA，≥44px 触控区）。
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(44, 48),
                                        foregroundColor: colors.brandPrimary,
                                      ),
                                      onPressed: () => unawaited(
                                        startCustomFoodFlow(context, ref),
                                      ),
                                      child: Text(
                                        cs.cta,
                                        style: textStyles.textBase.copyWith(
                                          color: colors.brandPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final resultsList = ListView.builder(
                        itemCount: foods.length,
                        itemBuilder: (context, index) {
                          final food = foods[index];
                          return ListTile(
                            title: Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    isEn ? food.nameEn : food.nameZh,
                                    style: textStyles.textBase,
                                  ),
                                ),
                                // 自定义/社区食物状态标签（K2 众包：自定义 /
                                // 审核中 / 已共享 / 未通过 / 社区，null 不显示）。
                                if (cs.badgeFor(food) case final badgeText?)
                                  Container(
                                    margin: const EdgeInsets.only(
                                      left: AppSpacing.s2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.s2,
                                      vertical: AppSpacing.s1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.brandAccent,
                                      borderRadius: radii.rSm,
                                    ),
                                    child: Text(
                                      badgeText,
                                      style: textStyles.textXs.copyWith(
                                        color: colors.bgPrimary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${food.kcalPer100g.round()} '
                              '${s.kcalUnit}/100${s.gramUnit}',
                              style: textStyles.textSm.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            onTap: () => _openFoodDetail(food),
                          );
                        },
                      );

                      // 搜索结果区滚动深度（§4.2 scroll_depth 组件级：
                      // component_id=search_results，容器内每档位只报一次）。
                      return ScrollDepthTracker(
                        page: 'record',
                        componentId: 'search_results',
                        child: resultsList,
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Text(
                        s.searchEmpty,
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                // 今日聚合（本地预估，§2.6 注明待云端校准；键盘顶起时
                // 收起此行给主流程让位，走查 Y1）。
                if (today != null && today.entryCount > 0 && !keyboardVisible)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s1,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.s2,
                        children: <Widget>[
                          Text(
                            '${s.loggedToday(today.entryCount)} · '
                            '${s.todayKcal(today.kcal.round())}',
                            style: textStyles.textSm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          // 断食期用餐标记（阶段 C：当日含断食窗口内入账记录时展示）。
                          if ((ref.watch(todayDuringFastCountProvider).value ??
                                  0) >
                              0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s2,
                                vertical: AppSpacing.s1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.brandAccent,
                                borderRadius: radii.rSm,
                              ),
                              child: Text(
                                s.duringFastBadge,
                                style: textStyles.textXs.copyWith(
                                  color: colors.bgPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                // 可编辑识别结果卡（食物名 + 份量 + 实时营养预览 + 确认）。
                if (selected != null)
                  _SelectedFoodCard(
                    food: selected,
                    isEn: isEn,
                    amountController: _amountController,
                    onConfirm: () => unawaited(_confirm(s)),
                    onClose: () {
                      ref.read(recordSelectedFoodProvider.notifier).state =
                          null;
                      ref.read(recordEntrySourceProvider.notifier).state =
                          EntrySource.manual;
                      ref.read(recordLowConfidenceProvider.notifier).state =
                          false;
                    },
                    shadows: shadows,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// EntrySource → 事件字典 entry_type 枚举（§3.3：photo → camera）。
  static String _entryEventType(EntrySource source) => switch (source) {
    EntrySource.photo => 'camera',
    EntrySource.voice => 'voice',
    EntrySource.frequent => 'frequent',
    EntrySource.manual => 'manual',
    EntrySource.barcode => 'barcode',
  };

  /// 按本地时间推断餐段（§3.3 meal_period；〔假设〕时段划分）。
  static String _mealPeriod() {
    final hour = DateTime.now().toLocal().hour;
    if (hour >= 5 && hour < 10) return 'breakfast';
    if (hour >= 10 && hour < 15) return 'lunch';
    if (hour >= 17 && hour < 21) return 'dinner';
    return 'snack';
  }
}

/// 三入口占位卡片（≥44px 触控区，M8 基线）。
///
/// [highlighted]（薄荷走查 P2）：拍照记主入口专用——主色描边 + 浅主色
/// 底 + 主色文字，与其余三格区分但同构（尺寸/圆角/阴影不变）。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: highlighted
              ? colors.brandPrimary.withValues(alpha: 0.08)
              : colors.bgSecondary,
          borderRadius: radii.rLg,
          child: InkWell(
            borderRadius: radii.rLg,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              decoration: BoxDecoration(
                borderRadius: radii.rLg,
                boxShadow: shadows.shadowSm,
                border: highlighted
                    ? Border.all(color: colors.brandPrimary, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: colors.brandPrimary),
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    label,
                    style: highlighted
                        ? textStyles.textSm.copyWith(
                            color: colors.brandPrimary,
                            fontWeight: FontWeight.w600,
                          )
                        : textStyles.textSm,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可编辑结果卡：食物名 + 份量编辑 + 营养实时重算 + 确认按钮。
class _SelectedFoodCard extends ConsumerWidget {
  const _SelectedFoodCard({
    required this.food,
    required this.isEn,
    required this.amountController,
    required this.onConfirm,
    required this.onClose,
    required this.shadows,
  });

  final Food food;
  final bool isEn;
  final TextEditingController amountController;
  final VoidCallback onConfirm;
  final VoidCallback onClose;
  final AppShadows shadows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final nutrition = ref.watch(recordDraftNutritionProvider);
    final lowConfidence = ref.watch(recordLowConfidenceProvider);

    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 低置信度标「请确认」（PRD M3：不直接入账高风险结果）。
          if (lowConfidence)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: colors.brandAccent,
                  borderRadius: radii.rSm,
                ),
                child: Text(
                  s.cardPleaseConfirm,
                  style: textStyles.textXs.copyWith(color: colors.bgPrimary),
                ),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isEn ? food.nameEn : food.nameZh,
                  style: textStyles.textLg,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
                tooltip: s.confirm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: textStyles.textBase,
            decoration: InputDecoration(
              labelText: s.amountLabel,
              filled: true,
              fillColor: colors.bgPrimary,
              border: OutlineInputBorder(
                borderRadius: radii.rMd,
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) =>
                ref.read(recordAmountTextProvider.notifier).state = value,
          ),
          const SizedBox(height: AppSpacing.s2),
          // 份量修改 → 营养换算实时更新（US-3.1）。
          if (nutrition != null)
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s1,
              children: <Widget>[
                _NutritionChip(
                  label: s.nutritionKcal,
                  value: '${nutrition.kcal.round()} ${s.kcalUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionProtein,
                  value:
                      '${nutrition.proteinG.toStringAsFixed(1)} '
                      '${s.gramUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionCarb,
                  value: '${nutrition.carbG.toStringAsFixed(1)} ${s.gramUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionFat,
                  value: '${nutrition.fatG.toStringAsFixed(1)} ${s.gramUnit}',
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
            child: Text(s.confirm, style: textStyles.textBase),
          ),
        ],
      ),
    );
  }
}

class _NutritionChip extends StatelessWidget {
  const _NutritionChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: radii.rSm,
      ),
      child: Text(
        '$label $value',
        style: textStyles.textXs.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
