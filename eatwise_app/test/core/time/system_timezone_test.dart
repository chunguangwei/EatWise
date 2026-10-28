import 'dart:async';

import 'package:eatwise/core/time/timezone_bootstrap.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eatwise/system_timezone');
  setUp(() {
    data.initializeTimeZones();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'reads actual New York identifier and retains future DST rules',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'America/New_York');
      bootstrapTimezone(null);
      await refreshSystemTimezone();
      expect(deviceLocationFallback().name, 'America/New_York');
      expect(
        tz.TZDateTime(deviceLocationFallback(), 2027, 1).timeZoneOffset,
        const Duration(hours: -5),
      );
      expect(
        tz.TZDateTime(deviceLocationFallback(), 2027, 7).timeZoneOffset,
        const Duration(hours: -4),
      );
    },
  );
  test(
    'invalid identifier and platform failure retain last verified location',
    () async {
      var identifier = 'America/Anguilla';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => identifier);
      await refreshSystemTimezone();
      identifier = 'Invalid/Region';
      await refreshSystemTimezone();
      expect(deviceLocationFallback().name, 'America/Anguilla');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'failed'),
          );
      await refreshSystemTimezone();
      expect(deviceLocationFallback().name, 'America/Anguilla');
    },
  );
  test('native event and resume update the location provider', () async {
    var identifier = 'America/New_York';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => identifier);
    bootstrapTimezone(null);
    await refreshSystemTimezone();
    final container = ProviderContainer();
    final subscription = container.listen(deviceLocationProvider, (_, _) {});
    expect(container.read(deviceLocationProvider).name, identifier);
    var refreshed = 0;
    final resumed = Completer<void>();
    final observer = SystemTimezoneObserver(
      onRefresh: () {
        refreshed++;
        if (refreshed == 2) resumed.complete();
      },
    );
    observer.start();
    addTearDown(observer.dispose);
    identifier = 'Asia/Tokyo';
    final delivered = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('timezoneChanged'),
      ),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await container.pump();
    expect(container.read(deviceLocationProvider).name, 'Asia/Tokyo');
    identifier = 'America/Anguilla';
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await resumed.future;
    await container.pump();
    expect(container.read(deviceLocationProvider).name, identifier);
    expect(refreshed, 2);
    subscription.close();
    container.dispose();
  });
}
