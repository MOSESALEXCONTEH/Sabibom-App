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
}
