import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本地日历日时钟。测试可注入可变时钟，生产直接使用 DateTime.now。
final Provider<DateTime Function()> localDayClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// 当前本地日历日（午夜归零），只在日期实际变化时更新。
final NotifierProvider<LocalDayController, DateTime> localDayProvider =
    NotifierProvider<LocalDayController, DateTime>(LocalDayController.new);

DateTime localDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String localDayKey(DateTime value) {
  final day = localDateOnly(value);
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-$month-$date';
}

/// 跨午夜与回前台的统一日变化源。午夜定时器和生命周期监听均在
/// Provider dispose 时清理；回前台不经过同步登录门或一分钟节流。
final class LocalDayController extends Notifier<DateTime>
    with WidgetsBindingObserver {
  DateTime Function()? _clock;
  Timer? _midnightTimer;
  WidgetsBinding? _binding;
  bool _initialized = false;
  bool _observing = false;
  bool _disposed = false;

  @override
  DateTime build() {
    final clock = ref.watch(localDayClockProvider);
    _clock = clock;
    if (!_initialized) {
      _initialized = true;
      try {
        final binding = WidgetsBinding.instance;
        binding.addObserver(this);
        _binding = binding;
        _observing = true;
      } on Object {
        // 无 WidgetsBinding 的纯 Dart 环境仍可使用定时器与手动 refresh。
      }
      ref.onDispose(_dispose);
    }
    _scheduleNextMidnight();
    return localDateOnly(clock());
  }

  /// 立即按当前时钟核对日期；测试与特殊生命周期入口也可显式调用。
  void refresh() {
    if (_disposed) return;
    final clock = _clock;
    if (clock == null) return;
    final nextDay = localDateOnly(clock());
    if (state != nextDay) state = nextDay;
    _scheduleNextMidnight();
  }

  void _scheduleNextMidnight() {
    _midnightTimer?.cancel();
    final clock = _clock;
    if (_disposed || clock == null) return;
    final now = clock().toLocal();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    var delay = nextMidnight.difference(now);
    if (delay <= Duration.zero) delay = const Duration(milliseconds: 1);
    _midnightTimer = Timer(delay, refresh);
  }

  void _dispose() {
    _disposed = true;
    _midnightTimer?.cancel();
    _midnightTimer = null;
    if (_observing) {
      _binding?.removeObserver(this);
      _observing = false;
    }
    _binding = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}
