import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 5 Tab 骨架（设计稿 §3.1 信息架构 / §4.1 导航：固定底栏 + 安全区，
/// 线性图标 24px、选中态轻盈绿填充、未选中雾灰）。
///
/// go_router StatefulShellRoute：首页（断食计时）/记录/数据/社区/我的
/// 五个分支，切换保留各分支状态（IndexedStack）。
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Tab 序 → 字典 page_id（§4.2 一级页）。
  static const List<String> _tabPageIds = <String>[
    'home',
    'record',
    'analytics',
    'community',
    'profile',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: colors.bgSecondary,
          indicatorColor: colors.brandPrimary.withValues(alpha: 0.16),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? colors.brandPrimary
                  : colors.textSecondary,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final base = textStyles.textXs;
            return states.contains(WidgetState.selected)
                ? base.copyWith(color: colors.brandPrimary)
                : base.copyWith(color: colors.textSecondary);
          }),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            navigationShell.goBranch(
              index,
              // 再次点按当前 Tab：回分支根路由（go_router 惯例）。
              initialLocation: index == navigationShell.currentIndex,
            );
            // 页面停留分段（§4.2：end_reason=tab_switch；同页重按 no-op）。
            ref.read(pageStayTrackerProvider).onTabSwitch(_tabPageIds[index]);
          },
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.timer_outlined),
              selectedIcon: const Icon(Icons.timer),
              label: t.home.tab.home,
            ),
            NavigationDestination(
              icon: const Icon(Icons.edit_note_outlined),
              selectedIcon: const Icon(Icons.edit_note),
              label: t.home.tab.record,
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: t.home.tab.data,
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: t.home.tab.community,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: t.home.tab.profile,
            ),
          ],
        ),
      ),
    );
  }
}
