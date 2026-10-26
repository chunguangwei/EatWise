import 'dart:async';

import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final values = <String, String>{};
  Completer<void>? started;
  Completer<void>? release;
  String? blockedMethod;
  String? blockedValue;
  var failNextRead = false;

  setUp(() {
    values.clear();
    started = null;
    release = null;
    blockedMethod = null;
    blockedValue = null;
    failNextRead = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments! as Map<dynamic, dynamic>;
      final key = args['key']! as String;
      if (call.method == blockedMethod &&
          key == 'eatwise.accessToken' &&
          (blockedValue == null || args['value'] == blockedValue)) {
        blockedMethod = null;
        started!.complete();
        await release!.future;
      }
      switch (call.method) {
        case 'read':
          if (failNextRead) {
            failNextRead = false;
            throw PlatformException(code: 'storage_unavailable');
          }
          return values[key];
        case 'write':
          values[key] = args['value']! as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
      }
      throw StateError('unexpected storage method ${call.method}');
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'a failed storage operation does not poison queued or later work',
    () async {
      final store = SecureTokenStore();
      await store.saveTokens(
        accessToken: 'A',
        refreshToken: 'A-r',
        userId: 'A',
      );
      failNextRead = true;
      final reading = store.accessToken;
      final queued = store.snapshot();
      await expectLater(reading, throwsA(isA<PlatformException>()));
      expect((await queued).accessToken, 'A');
      await store.saveTokens(
        accessToken: 'B',
        refreshToken: 'B-r',
        userId: 'B',
      );
      expect((await store.snapshot()).userId, 'B');
    },
  );

  test(
    'a rotation already writing to secure storage cannot overwrite the next login',
    () async {
      final store = SecureTokenStore();
      await store.saveTokens(
        accessToken: 'A',
        refreshToken: 'A-r',
        userId: 'A',
      );
      started = Completer<void>();
      release = Completer<void>();
      blockedMethod = 'write';
      blockedValue = 'A-new';
      final rotating = store.rotateIfCurrent(
        epoch: store.sessionEpoch,
        accessToken: 'A-new',
        refreshToken: 'A-new-r',
      );
      await started!.future;
      final clearing = store.clear();
      final login = store.saveTokens(
        accessToken: 'B',
        refreshToken: 'B-r',
        userId: 'B',
      );
      release!.complete();
      expect(await rotating, isFalse);
      await clearing;
      await login;
      expect(await store.accessToken, 'B');
      expect(await store.refreshToken, 'B-r');
      expect(await store.userId, 'B');
    },
  );

  test(
    'a snapshot queued before login never labels old tokens with the new epoch',
    () async {
      final store = SecureTokenStore();
      await store.saveTokens(
        accessToken: 'A',
        refreshToken: 'A-r',
        userId: 'A',
      );
      final oldEpoch = store.sessionEpoch;
      started = Completer<void>();
      release = Completer<void>();
      blockedMethod = 'read';
      final reading = store.accessToken;
      await started!.future;
      final snapshot = store.snapshot();
      final login = store.saveTokens(
        accessToken: 'B',
        refreshToken: 'B-r',
        userId: 'B',
      );
      release!.complete();
      await reading;
      final old = await snapshot;
      expect(old.accessToken, 'A');
      expect(old.epoch, oldEpoch);
      expect(old.epoch, isNot(store.sessionEpoch));
      await login;
      expect((await store.snapshot()).accessToken, 'B');
    },
  );
}
