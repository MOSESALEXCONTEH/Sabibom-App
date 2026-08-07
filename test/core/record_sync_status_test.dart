import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/sync/record_sync_status.dart';

void main() {
  test('requests with the same document path are equal', () {
    const first = RecordSyncRequest(
      businessId: 'business-1',
      collection: 'sales',
      recordId: 'sale-1',
    );
    const second = RecordSyncRequest(
      businessId: 'business-1',
      collection: 'sales',
      recordId: 'sale-1',
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('reports a committed Firestore record as synced', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('businesses')
        .doc('business-1')
        .collection('sales')
        .doc('sale-1')
        .set(<String, Object?>{'totalMinor': 1000});
    final container = ProviderContainer(
      overrides: [recordSyncFirestoreProvider.overrideWithValue(firestore)],
    );
    addTearDown(container.dispose);

    final provider = recordSyncStatusProvider(
      const RecordSyncRequest(
        businessId: 'business-1',
        collection: 'sales',
        recordId: 'sale-1',
      ),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final status = await container.read(provider.future);

    expect(status.phase, RecordSyncPhase.synced);
  });

  test('rejects an incomplete record path as failed', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final provider = recordSyncStatusProvider(
      const RecordSyncRequest(
        businessId: '',
        collection: 'sales',
        recordId: 'sale-1',
      ),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final status = await container.read(provider.future);

    expect(status.phase, RecordSyncPhase.failed);
  });

  test('reports a missing Firestore record as failed', () async {
    final firestore = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides: [recordSyncFirestoreProvider.overrideWithValue(firestore)],
    );
    addTearDown(container.dispose);

    final provider = recordSyncStatusProvider(
      const RecordSyncRequest(
        businessId: 'business-1',
        collection: 'sales',
        recordId: 'missing-sale',
      ),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final status = await container.read(provider.future);

    expect(status.phase, RecordSyncPhase.failed);
  });
}
