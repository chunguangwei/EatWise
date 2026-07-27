import 'package:eatwise/features/demo/presentation/demo_home_screen.dart';
import 'package:go_router/go_router.dart';

/// 应用路由表（go_router，D-17）。
///
/// M0 基建阶段仅挂一个演示页，验证主题与双语可用；
/// 5 Tab ShellRoute 结构随各 feature 页面落地后扩展。
final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const DemoHomeScreen()),
  ],
);
