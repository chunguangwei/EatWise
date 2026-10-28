/// System IANA timezone shared by rendering, HTTP headers and scheduling.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

bool _bootstrapDone = false;
final _timezoneRevision = ValueNotifier<int>(0);
const _channel = MethodChannel('eatwise/system_timezone');
int _refreshGeneration = 0;

/// Only consumers of the location rebuild, without recreating HTTP clients.
final systemTimezoneRevisionProvider = Provider<int>((ref) {
  void changed() => ref.invalidateSelf();
  _timezoneRevision.addListener(changed);
  ref.onDispose(() => _timezoneRevision.removeListener(changed));
  return _timezoneRevision.value;
});

/// Load the database before querying native code. Never infer a region from an
/// offset: equal offsets today can have different DST rules tomorrow.
void bootstrapTimezone(Uint8List? tzfData) {
  try {
    if (tzfData != null) tz.initializeDatabase(tzfData);
  } on Object {
    // Keep startup usable when the bundled database is unavailable.
  }
  tz.setLocalLocation(tz.UTC);
  _bootstrapDone = true;
}

/// Invalid identifiers and missing platform bridges retain the last verified
/// location. On first launch bootstrap has already installed UTC.
Future<void> refreshSystemTimezone() async {
  final generation = ++_refreshGeneration;
  try {
    final identifier = await _channel
        .invokeMethod<String>('getIdentifier')
        .timeout(const Duration(seconds: 2));
    if (generation != _refreshGeneration || identifier == null) return;
    final location = tz.getLocation(identifier);
    if (tz.local.name == location.name) return;
    tz.setLocalLocation(location);
    _timezoneRevision.value++;
  } on Object {
    // A later native event or foreground refresh retries safely.
  }
}

/// Native events handle an open foreground app; resume covers missed events
/// while suspended. Owned by main for the lifetime of the application.
final class SystemTimezoneObserver with WidgetsBindingObserver {
  SystemTimezoneObserver({this.onRefresh});
  final VoidCallback? onRefresh;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'timezoneChanged') await refresh();
    });
  }

  Future<void> refresh() async {
    await refreshSystemTimezone();
    onRefresh?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
  }
}

/// 设备时区的统一读取口径（deviceLocationProvider / 各仓储默认值共用）。
/// 未装配（纯单测/预览）回退 Asia/Shanghai（〔假设〕MVP 上架中国区，
/// 与历史口径一致）；时区库缺失再回 UTC。
tz.Location deviceLocationFallback() {
  if (_bootstrapDone) {
    try {
      return tz.local;
    } on Object {
      return tz.UTC;
    }
  }
  try {
    return tz.getLocation('Asia/Shanghai');
  } on Object {
    return tz.UTC;
  }
}
