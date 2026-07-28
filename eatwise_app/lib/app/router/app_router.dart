import 'package:eatwise/features/demo/presentation/demo_home_screen.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/presentation/questionnaire_screen.dart';
import 'package:eatwise/features/onboarding/presentation/recommendation_screen.dart';
import 'package:eatwise/features/onboarding/presentation/science_card_screen.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:go_router/go_router.dart';

/// 应用路由表（go_router，D-17）。
///
/// M1：首次进入（引导未完成）重定向到 /onboarding 问卷流；
/// 一键启动完成后（[OnboardingGate.completed] = true）进首页。
/// 首页暂为 M0 演示页占位，5 Tab ShellRoute 结构随各 feature 页面落地后扩展。
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
      GoRoute(path: '/', builder: (context, state) => const DemoHomeScreen()),
      GoRoute(path: '/record', builder: (context, state) => const RecordPage()),
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
