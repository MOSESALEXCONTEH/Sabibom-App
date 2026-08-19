import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/sync/offline_mutation_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'persists queued branch-owned mutations across queue instances',
    () async {
      final first = OfflineMutationQueue(currentUserId: () => 'user-1');
      await first.enqueue(
        id: 'product-product-1',
        type: OfflineMutationType.productCreate,
        businessId: 'business-1',
        payload: <String, dynamic>{
          'productId': 'product-1',
          'branchId': 'east',
          'name': 'Rice',
          'quantity': 12,
        },
      );

      final restored = OfflineMutationQueue(currentUserId: () => 'user-1');
      final pending = await restored.pending(businessId: 'business-1');

      expect(pending, hasLength(1));
      expect(pending.single.type, OfflineMutationType.productCreate);
      expect(pending.single.payload['branchId'], 'east');
      expect(pending.single.payload['quantity'], 12);
    },
  );

  test('does not expose one users queued writes to another user', () async {
    final owner = OfflineMutationQueue(currentUserId: () => 'owner');
    await owner.enqueue(
      id: 'sale-sale-1',
      type: OfflineMutationType.saleComplete,
      businessId: 'business-1',
      payload: <String, dynamic>{
        'request': <String, dynamic>{'branchId': 'east'},
      },
    );

    final staff = OfflineMutationQueue(currentUserId: () => 'staff');
    expect(await staff.pending(), isEmpty);
  });

  test(
    're-enqueueing a deterministic id replaces instead of duplicating',
    () async {
      final queue = OfflineMutationQueue(currentUserId: () => 'user-1');
      await queue.enqueue(
        id: 'sale-sale-1',
        type: OfflineMutationType.saleComplete,
        businessId: 'business-1',
        payload: <String, dynamic>{'version': 1},
      );
      await queue.enqueue(
        id: 'sale-sale-1',
        type: OfflineMutationType.saleComplete,
        businessId: 'business-1',
        payload: <String, dynamic>{'version': 2},
      );

      final pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.payload['version'], 2);
    },
  );

  test('persists a pending purchase command and its local summary', () async {
    final queue = OfflineMutationQueue(currentUserId: () => 'user-1');
    await queue.enqueue(
      id: 'purchase-purchase-1',
      type: OfflineMutationType.purchaseComplete,
      businessId: 'business-1',
      payload: <String, dynamic>{
        'request': <String, dynamic>{
          'purchaseId': 'purchase-1',
          'branchId': 'east',
        },
        'summary': <String, dynamic>{
          'purchaseId': 'purchase-1',
          'branchId': 'east',
          'totalMinor': 2500,
        },
      },
    );

    final restored = OfflineMutationQueue(currentUserId: () => 'user-1');
    final pending = await restored.pending(businessId: 'business-1');
    expect(pending.single.type, OfflineMutationType.purchaseComplete);
    expect((pending.single.payload['summary'] as Map)['branchId'], 'east');
  });

  test('quarantines malformed storage instead of losing it silently', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      OfflineMutationQueue.storageKey: '{not-json',
    });
    final queue = OfflineMutationQueue(
      currentUserId: () => 'user-1',
      now: () => DateTime.utc(2026, 8, 18),
    );

    expect(await queue.pending(), isEmpty);
    final quarantined = await queue.quarantined();
    expect(quarantined, hasLength(1));
    expect(quarantined.single.reason, 'malformed_queue');
    expect(quarantined.single.raw, '{not-json');

    final prefs = await SharedPreferences.getInstance();
    final repaired =
        jsonDecode(prefs.getString(OfflineMutationQueue.storageKey)!)
            as Map<String, dynamic>;
    expect(repaired['version'], OfflineMutationQueue.envelopeVersion);
  });

  test('migrates a legacy list while retaining damaged entries', () async {
    final healthy = <String, dynamic>{
      'id': 'sale-sale-1',
      'type': OfflineMutationType.saleComplete.name,
      'userId': 'user-1',
      'businessId': 'business-1',
      'payload': <String, dynamic>{'request': <String, dynamic>{}},
      'createdAt': DateTime.utc(2026, 8, 18).toIso8601String(),
    };
    SharedPreferences.setMockInitialValues(<String, Object>{
      OfflineMutationQueue.storageKey: jsonEncode(<Object?>[healthy, 'broken']),
    });
    final queue = OfflineMutationQueue(currentUserId: () => 'user-1');

    expect(await queue.pending(), hasLength(1));
    final quarantined = await queue.quarantined();
    expect(quarantined, hasLength(1));
    expect(quarantined.single.reason, 'malformed_mutation');
    expect(quarantined.single.raw, 'broken');
  });

  test(
    'backs off transient failures and retries only after due time',
    () async {
      var now = DateTime.utc(2026, 8, 18, 12);
      var executions = 0;
      final queue = OfflineMutationQueue(
        currentUserId: () => 'user-1',
        now: () => now,
        executeOverride: (_) async {
          executions++;
          if (executions == 1) throw Exception('offline');
        },
      );
      await queue.enqueue(
        id: 'sale-sale-1',
        type: OfflineMutationType.saleComplete,
        businessId: 'business-1',
        payload: <String, dynamic>{},
      );

      await queue.syncPending();
      var pending = await queue.pending();
      expect(executions, 1);
      expect(pending.single.attemptCount, 1);
      expect(
        pending.single.nextAttemptAt,
        now.add(const Duration(seconds: 30)),
      );

      await queue.syncPending();
      expect(executions, 1);

      now = now.add(const Duration(seconds: 30));
      await queue.syncPending();
      pending = await queue.pending();
      expect(executions, 2);
      expect(pending, isEmpty);
    },
  );

  test('quarantines terminal failures and removes them from pending', () async {
    final queue = OfflineMutationQueue(
      currentUserId: () => 'user-1',
      now: () => DateTime.utc(2026, 8, 18),
      executeOverride: (_) async => throw StateError('invalid payload'),
    );
    await queue.enqueue(
      id: 'product-product-1',
      type: OfflineMutationType.productCreate,
      businessId: 'business-1',
      payload: <String, dynamic>{},
    );

    await queue.syncPending();

    expect(await queue.pending(), isEmpty);
    final quarantined = await queue.quarantined();
    expect(quarantined, hasLength(1));
    expect(quarantined.single.reason, 'terminal_error');
    expect(quarantined.single.mutation?.id, 'product-product-1');
  });

  test('coalesces concurrent sync triggers into one replay pass', () async {
    var executions = 0;
    final queue = OfflineMutationQueue(
      currentUserId: () => 'user-1',
      executeOverride: (_) async {
        executions++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );
    await queue.enqueue(
      id: 'sale-sale-1',
      type: OfflineMutationType.saleComplete,
      businessId: 'business-1',
      payload: <String, dynamic>{},
    );

    await Future.wait(<Future<void>>[
      queue.syncPending(),
      queue.syncPending(),
      queue.syncPending(),
    ]);

    expect(executions, 1);
    expect(await queue.pending(), isEmpty);
  });
}
