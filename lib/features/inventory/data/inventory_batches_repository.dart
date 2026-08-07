import 'package:cloud_firestore/cloud_firestore.dart';

import '../../branches/domain/business_branch.dart';
import '../domain/inventory_batch.dart';

abstract interface class InventoryBatchesRepository {
  Stream<List<InventoryBatch>> watchProductBatches(
    String businessId,
    String productId, {
    int limit = 100,
    String? branchId,
  });

  Future<List<InventoryBatch>> loadAttentionBatches(
    String businessId, {
    int limit = 200,
    String? branchId,
  });
}

class FirestoreInventoryBatchesRepository
    implements InventoryBatchesRepository {
  FirestoreInventoryBatchesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _batches(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('inventory_batches');

  @override
  Stream<List<InventoryBatch>> watchProductBatches(
    String businessId,
    String productId, {
    int limit = 100,
    String? branchId,
  }) {
    if (businessId.trim().isEmpty || productId.trim().isEmpty) {
      return Stream<List<InventoryBatch>>.value(const <InventoryBatch>[]);
    }
    return _batches(businessId)
        .where('productId', isEqualTo: productId)
        .orderBy('receivedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(InventoryBatch.fromFirestore)
              .toList(),
        );
  }

  @override
  Future<List<InventoryBatch>> loadAttentionBatches(
    String businessId, {
    int limit = 200,
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) return const <InventoryBatch>[];
    final snapshot = await _batches(businessId)
        .where('status', whereIn: const <String>['active', 'expired'])
        .orderBy('expiryDate')
        .limit(limit)
        .get();
    return snapshot.docs
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(InventoryBatch.fromFirestore)
        .toList();
  }
}
