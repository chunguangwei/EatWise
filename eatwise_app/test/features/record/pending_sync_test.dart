import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/application/pending_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'session change cancels old account feedback without reading new data',
    () async {
      var reads = 0;
      expect(
        await retryPendingRecords(
          sync: () async {
            throw const SessionChangedException();
          },
          readErrors: () async {
            reads++;
            return [];
          },
        ),
        PendingSyncResult.cancelled,
      );
      expect(reads, 0);
    },
  );

  test('timeout and authentication errors retain their reason', () async {
    expect(
      await retryPendingRecords(
        sync: () async {},
        readErrors: () async => ['TIMEOUT'],
      ),
      PendingSyncResult.timeout,
    );
    expect(
      await retryPendingRecords(
        sync: () async {},
        readErrors: () async => ['AUTH_TOKEN_INVALID'],
      ),
      PendingSyncResult.login,
    );
    expect(
      await retryPendingRecords(
        sync: () async {},
        readErrors: () async => ['INTERNAL_ERROR'],
      ),
      PendingSyncResult.server,
    );
  });
  test('pull failure cannot turn an empty queue into success', () async {
    expect(
      await retryPendingRecords(
        sync: () async {
          throw const NetworkApiException();
        },
        readErrors: () async => [],
      ),
      PendingSyncResult.network,
    );
  });

  test(
    'manual retry waits for upload and reads persisted network failure',
    () async {
      var uploaded = false;
      final result = await retryPendingRecords(
        sync: () async {
          uploaded = true;
        },
        readErrors: () async {
          expect(uploaded, isTrue);
          return ['NETWORK_ERROR'];
        },
      );
      expect(result, PendingSyncResult.network);
    },
  );
  test('empty pending queue after upload succeeds', () async {
    expect(
      await retryPendingRecords(sync: () async {}, readErrors: () async => []),
      PendingSyncResult.success,
    );
  });
  test('undo window without an error stays pending', () async {
    expect(
      await retryPendingRecords(
        sync: () async {},
        readErrors: () async => [null],
      ),
      PendingSyncResult.pending,
    );
  });
  test('server rollback must not be reported as successful upload', () async {
    expect(
      await retryPendingRecords(
        sync: () async {},
        readErrors: () async => [],
        wasRejected: () => true,
      ),
      PendingSyncResult.rejected,
    );
  });
}
