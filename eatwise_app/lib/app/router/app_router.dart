import 'package:eatwise/features/demo/presentation/demo_home_screen.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/home/presentation/home_shell.dart';
import 'package:eatwise/features/home/presentation/placeholder_pages.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/presentation/questionnaire_screen.dart';
import 'package:eatwise/features/onboarding/presentation/recommendation_screen.dart';
import 'package:eatwise/features/onboarding/presentation/science_card_screen.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:go_router/go_router.dart';

/// 应用路由表（go_router，D-17）。
///
/// `/` 起为 5 Tab StatefulShellRoute（设计稿 §3.1）：
/// 首页（断食计时）/记录/数据/社区/我的，底栏固定，切换保留分支状态。
/// M1：首次进入（引导未完成）重定向到 /onboarding 问卷流；
/// 一键启动完成后（[OnboardingGate.completed] = true）进首页。
GoRouter createAppRouter({required OnboardingGate gate}) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!gate.completed && !onOnboarding) return '/onboarding';
      if (gate.completed && onOnboarding) return '/';
      return null;
    },
    routes: <RouteBase>[
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
          // 数据：M4 占位（四态空态 + 去记录 CTA）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/data',
                builder: (context, state) => const DataPlaceholderPage(),
              ),
            ],
          ),
          // 社区：M5 占位（四态空态 + 即将上线提示）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/community',
                builder: (context, state) => const CommunityPlaceholderPage(),
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
