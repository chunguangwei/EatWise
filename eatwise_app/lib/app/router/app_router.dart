import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/presentation/login_page.dart';
import 'package:eatwise/features/demo/presentation/demo_home_screen.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/home/presentation/home_shell.dart';
import 'package:eatwise/features/home/presentation/placeholder_pages.dart';
import 'package:eatwise/features/nutrition/presentation/nutrition_data_page.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/presentation/questionnaire_screen.dart';
import 'package:eatwise/features/onboarding/presentation/recommendation_screen.dart';
import 'package:eatwise/features/onboarding/presentation/science_card_screen.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/social/presentation/community_feed_page.dart';
import 'package:eatwise/features/social/presentation/compose_page.dart';
import 'package:go_router/go_router.dart';

/// 应用路由表（go_router，D-17）。
///
/// `/` 起为 5 Tab StatefulShellRoute（设计稿 §3.1）：
/// 首页（断食计时）/记录/数据/社区/我的，底栏固定，切换保留分支状态。
/// M1：首次进入（引导未完成）重定向到 /onboarding 问卷流；
/// 一键启动完成后（[OnboardingGate.completed] = true）进首页。
/// D-13：登录门禁（[AuthGate]，可空——缺省视为已登录，保留 M0 演示路径）：
/// 未登录 → /login；已登录 → 按引导门禁走 /onboarding 或首页。
/// 登录态与引导完成是两个独立标志。
GoRouter createAppRouter({required OnboardingGate gate, AuthGate? authGate}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: authGate,
    redirect: (context, state) {
      final loggedIn = authGate?.loggedIn ?? true;
      final onLogin = state.matchedLocation == '/login';
      final onOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!loggedIn) return onLogin ? null : '/login';
      if (onLogin) return gate.completed ? '/' : '/onboarding';
      if (!gate.completed && !onOnboarding) return '/onboarding';
      if (gate.completed && onOnboarding) return '/';
      return null;
    },
    routes: <RouteBase>[
      // D-13 登录页（独立路由，不进 Tab Shell）。
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          // 首页：断食计时主页。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (context, state) => const FastingHomePage(),
              ),
            ],
          ),
          // 记录：M3 记录页。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/record',
                builder: (context, state) => const RecordPage(),
              ),
            ],
          ),
          // 数据：M4 营养数据页（信号灯四卡 + 趋势 + 专业数据折叠）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/data',
                builder: (context, state) => const NutritionDataPage(),
              ),
            ],
          ),
          // 社区：M5 打卡流（单列卡片）+ 发布页（FAB 进入）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/community',
                builder: (context, state) => const CommunityFeedPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'compose',
                    builder: (context, state) => const ComposePage(),
                  ),
                ],
              ),
            ],
          ),
          // 我的：M7 占位（四态空态 + 语言设置，D-15）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePlaceholderPage(),
              ),
            ],
          ),
        ],
      ),
      // M0 基建演示页保留在次要路由（Token/双语示例）。
      GoRoute(
        path: '/demo',
        builder: (context, state) => const DemoHomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const QuestionnaireScreen(),
      ),
      GoRoute(
        path: '/onboarding/recommendation',
        builder: (context, state) => const RecommendationScreen(),
      ),
      GoRoute(
        path: '/onboarding/science',
        builder: (context, state) => const ScienceCardScreen(),
      ),
    ],
  );
}
