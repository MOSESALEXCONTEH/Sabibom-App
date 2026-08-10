import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/inventory_batches_repository.dart';
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
  final branchId = ref.watch(currentBranchProvider).when(
    data: (selection) => selection?.selectedBranch.branchId,
    loading: () => null,
    error: (_, _) => null,
  );
  return ref
      .watch(inventoryBatchesRepositoryProvider)
      .watchProductBatches(request.$1, request.$2, branchId: branchId);
});

final inventoryAttentionBatchesProvider =
    FutureProvider.family<List<InventoryBatch>, String>((ref, businessId) {
      final branchId = ref.watch(currentBranchProvider).when(
        data: (selection) => selection?.selectedBranch.branchId,
        loading: () => null,
        error: (_, _) => null,
      );
      return ref
          .watch(inventoryBatchesRepositoryProvider)
          .loadAttentionBatches(businessId, branchId: branchId);
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
