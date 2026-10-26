import 'dart:async';

import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTokenStore store;

  // Providers/stores are commonly constructed outside WidgetTest's FakeAsync.
  setUp(() {
    store = InMemoryTokenStore();
  });

  testWidgets('first token write completes in the widget caller zone', (
    tester,
  ) async {
    var completed = false;
    unawaited(
      store
          .saveTokens(accessToken: 'A', refreshToken: 'A-r', userId: 'A')
          .then((_) => completed = true),
    );
    await tester.pump();
    expect(completed, isTrue);
    expect(await store.accessToken, 'A');
  });
}
