import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/inventory_batches_repository.dart';
import '../domain/branch_inventory.dart';
import '../domain/inventory_batch.dart';
import '../domain/inventory_expiry_settings.dart';

final inventoryBatchesRepositoryProvider =
    Provider<InventoryBatchesRepository>(
      (ref) => FirestoreInventoryBatchesRepository(),
    );

final productInventoryBatchesProvider = StreamProvider.family<
  List<InventoryBatch>,
  (String businessId, String productId)
>((ref, request) {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  return ref
      .watch(inventoryBatchesRepositoryProvider)
      .watchProductBatches(request.$1, request.$2, branchId: branchId);
});

final inventoryAttentionBatchesProvider =
    FutureProvider.family<List<InventoryBatch>, String>((ref, businessId) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(inventoryBatchesRepositoryProvider)
          .loadAttentionBatches(businessId, branchId: branchId);
    });


final productBranchInventoryBreakdownProvider = StreamProvider.family<
    List<BranchInventory>, (String businessId, String productId)>((ref, request) {
  if (request.$1.trim().isEmpty || request.$2.trim().isEmpty) {
    return Stream.value(const <BranchInventory>[]);
  }
  return FirebaseFirestore.instance
      .collectionGroup('inventory')
      .where('businessId', isEqualTo: request.$1)
      .where('productId', isEqualTo: request.$2)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map(BranchInventory.fromFirestore)
            .where((row) =>
                row.businessId == request.$1 && row.productId == request.$2)
            .toList(growable: false)
          ..sort((left, right) => left.branchId.compareTo(right.branchId));
        return rows;
      });
});

final inventoryExpirySettingsProvider =
    StreamProvider.family<InventoryExpirySettings, String>((ref, businessId) {
      if (businessId.trim().isEmpty) {
        return Stream.value(const InventoryExpirySettings());
      }
      return FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .collection('settings')
          .doc('inventory_expiry')
          .snapshots()
          .map((snap) {
            final data = snap.data();
            if (data == null) return const InventoryExpirySettings();
            return InventoryExpirySettings.fromMap(data);
          });
    });

Future<void> saveInventoryExpirySettings({
  required String businessId,
  required InventoryExpirySettings settings,
}) async {
  await FirebaseFirestore.instance
      .collection('businesses')
      .doc(businessId)
      .collection('settings')
      .doc('inventory_expiry')
      .set({
        ...settings.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
