import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (ref) => FirestorePurchasesRepository(),
);

final purchasesProvider = StreamProvider.family<List<Purchase>, String>(
  (ref, businessId) {
    final branchId = ref.watch(currentBranchReadScopeProvider);
    return ref.watch(purchasesRepositoryProvider).watchPurchases(businessId, branchId: branchId);
  },
);

final purchaseProvider = FutureProvider.family<Purchase?, (String, String)>(
  (ref, request) {
    final branchId = ref.watch(currentBranchReadScopeProvider);
    return ref
        .watch(purchasesRepositoryProvider)
        .getPurchase(request.$1, request.$2, branchId: branchId);
  },
);
