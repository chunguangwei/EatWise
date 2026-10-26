import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/token_store.dart';

const sessionTokenStoreKey = 'eatwise.sessionTokenStore';
const requestSessionLeaseKey = 'eatwise.requestSessionLease';
final _sessionZoneKey = Object();

/// One immutable login identity, inherited by every async child operation.
/// Refresh rotates credentials inside the lease; logout/relogin invalidates it.
final class SessionLease {
  SessionLease(this.store) : epoch = store.sessionEpoch;

  final TokenStore store;
  final int epoch;
  bool _disposed = false;

  bool get isCurrent => !_disposed && store.sessionEpoch == epoch;
  void dispose() => _disposed = true;
  void check() {
    if (!isCurrent) throw const SessionChangedException();
  }

  static SessionLease? get current =>
      Zone.current[_sessionZoneKey] as SessionLease?;

  static SessionLease? capture(Dio dio) {
    final inherited = current;
    if (inherited != null) return inherited;
    final store = dio.options.extra[sessionTokenStoreKey];
    return store is TokenStore ? SessionLease(store) : null;
  }

  Future<T> run<T>(Future<T> Function() work) => runZoned(() async {
    check();
    return work();
  }, zoneValues: {_sessionZoneKey: this});
}

void checkActiveSession() => SessionLease.current?.check();

Future<T> withApiSession<T>(
  Dio dio,
  Future<T> Function() work, {
  String? userId,
}) {
  final lease = SessionLease.capture(dio);
  if (lease == null) return work();
  return lease.run(() async {
    if (userId != null) {
      final snapshot = await lease.store.snapshot();
      lease.check();
      if (snapshot.epoch != lease.epoch ||
          (snapshot.userId ?? 'anonymous') != userId) {
        throw const SessionChangedException();
      }
    }
    return work();
  });
}
