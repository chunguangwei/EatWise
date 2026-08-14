import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/auth/application/auth_gate.dart';
import 'package:eatwise/features/auth/presentation/login_page.dart';
import 'package:eatwise/features/demo/presentation/demo_home_screen.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/home/presentation/home_shell.dart';
import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/presentation/legal_pages.dart';
import 'package:eatwise/features/legal/presentation/privacy_consent_page.dart';
import 'package:eatwise/features/nutrition/presentation/nutrition_data_page.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/presentation/questionnaire_screen.dart';
import 'package:eatwise/features/onboarding/presentation/recommendation_screen.dart';
import 'package:eatwise/features/onboarding/presentation/science_card_screen.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/reports/presentation/reports_page.dart';
import 'package:eatwise/features/settings/presentation/ai_model_settings_page.dart';
import 'package:eatwise/features/settings/presentation/settings_page.dart';
import 'package:eatwise/features/social/presentation/community_feed_page.dart';
import 'package:eatwise/features/social/presentation/compose_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 应用路由表（go_router，D-17）。
///
/// `/` 起为 5 Tab StatefulShellRoute（设计稿 §3.1）：
/// 首页（断食计时）/记录/数据/社区/我的，底栏固定，切换保留分支状态。
/// D-18：首启隐私门禁（[PrivacyGate]，可空——缺省视为已同意，保留既有
/// 测试/演示路径）：未同意主隐私政策 → /legal/consent（在任何数据上报
/// 之前拦截；/legal/* 协议正文同意前可读）。
/// M1：首次进入（引导未完成）重定向到 /onboarding 问卷流；
/// 一键启动完成后（[OnboardingGate.completed] = true）进首页。
/// D-13：登录门禁（[AuthGate]，可空——缺省视为已登录，保留 M0 演示路径）：
/// 未登录 → /login；已登录 → 按引导门禁走 /onboarding 或首页。
/// 隐私同意、登录态与引导完成是三个独立标志，按序拦截。
GoRouter createAppRouter({
  required OnboardingGate gate,
  AuthGate? authGate,
  PrivacyGate? privacyGate,
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) {
  return GoRouter(
    initialLocation: '/',
    observers: observers,
    refreshListenable: Listenable.merge(<Listenable?>[authGate, privacyGate]),
    redirect: (context, state) {
      final privacyAgreed = privacyGate?.agreed ?? true;
      final location = state.matchedLocation;
      final onLegal = location.startsWith('/legal');
      // 隐私门禁优先：未同意 → 仅允许停留 /legal/*（弹窗页与协议正文）。
      if (!privacyAgreed) {
        return onLegal ? null : '/legal/consent';
      }
      final loggedIn = authGate?.loggedIn ?? true;
      final onLogin = location == '/login';
      final onOnboarding = location.startsWith('/onboarding');
      if (!loggedIn) return onLogin ? null : '/login';
      if (onLogin) return gate.completed ? '/' : '/onboarding';
      if (!gate.completed && !onOnboarding) return '/onboarding';
      // 同意后停留在弹窗页 → 按登录/引导门禁送到应去页面。
      if (gate.completed && (onOnboarding || location == '/legal/consent')) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      // D-18 首启隐私弹窗与协议正文（独立路由，不进 Tab Shell）。
      GoRoute(
        path: '/legal/consent',
        builder: (context, state) => const PrivacyConsentPage(),
      ),
      GoRoute(
        path: '/legal/privacy',
        builder: (context, state) {
          final t = Translations.of(context);
          return LegalDocumentPage(
            title: t.legal.privacyPolicy.title,
            body: t.legal.privacyPolicy.body,
          );
        },
      ),
      GoRoute(
        path: '/legal/agreement',
        builder: (context, state) {
          final t = Translations.of(context);
          return LegalDocumentPage(
            title: t.legal.userAgreement.title,
            body: t.legal.userAgreement.body,
          );
        },
      ),
      GoRoute(
        path: '/legal/disclaimer',
        builder: (context, state) => const DisclaimerPage(),
      ),
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
          // 数据：M4 营养数据页（信号灯四卡 + 趋势 + 专业数据折叠）
          // + M6 趋势与深度报告二级页（/data/reports）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/data',
                builder: (context, state) => const NutritionDataPage(),
                routes: <RouteBase>[
                  // M6：趋势与深度报告二级页。
                  GoRoute(
                    path: 'reports',
                    builder: (context, state) => const ReportsPage(),
                  ),
                ],
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
          // 我的：M7 设置页（账号/隐私/偏好/提醒/关于，合规 D-18）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const SettingsPage(),
              ),
              // 用户自定义 LLM 配置（偏好组入口，与 /profile 同层）。
              GoRoute(
                path: '/settings/ai-model',
                builder: (context, state) => const AiModelSettingsPage(),
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
