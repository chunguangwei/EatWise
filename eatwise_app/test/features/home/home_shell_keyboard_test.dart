import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/home/presentation/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'keyboard reaches page and notification can be dismissed while editing on $platform',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        double inset = 0;
        late BuildContext pageContext;
        final router = GoRouter(
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) =>
                  HomeShell(navigationShell: shell),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/',
                      builder: (context, state) {
                        inset = MediaQuery.viewInsetsOf(context).bottom;
                        return Scaffold(
                          body: Builder(
                            builder: (context) {
                              pageContext = context;
                              return const SingleChildScrollView(
                                child: Column(
                                  children: [
                                    SizedBox(height: 480),
                                    TextField(key: ValueKey('input')),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          TranslationProvider(
            child: ProviderScope(
              child: MaterialApp.router(
                theme: AppTheme.light().copyWith(platform: platform),
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('input')));
        final originalInput = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(inset, 300);
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(originalInput),
        );
        expect(originalInput.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.testTextInput.enterText('first');
        await tester.pump();
        expect(find.text('first'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: const Text('Saved'),
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final snack = tester.getRect(find.byType(SnackBar));
        expect(snack.bottom, lessThanOrEqualTo(544));
        // A persistent undo notice must remain dismissible while the keyboard is
        // open, without forcing the user to leave the form or wait for timeout.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        await tester.ensureVisible(find.byKey(const ValueKey('input')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('input'))).bottom,
          lessThanOrEqualTo(544),
        );
        await tester.enterText(find.byKey(const ValueKey('input')), '120');
        expect(find.text('120'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
