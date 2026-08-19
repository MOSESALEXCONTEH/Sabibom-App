import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/offline_mutation_queue.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../notifications/application/transaction_notification_service.dart';
import '../data/notifying_purchases_repository.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (ref) => NotifyingPurchasesRepository(
    FirestorePurchasesRepository(
      offlineQueue: ref.watch(offlineMutationQueueProvider),
    ),
    ref.watch(transactionNotificationServiceProvider),
  ),
);

final purchasesProvider = StreamProvider.family<List<Purchase>, String>((
  ref,
  businessId,
) {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  final source = ref
      .watch(purchasesRepositoryProvider)
      .watchPurchases(businessId, branchId: branchId);
  final queue = ref.watch(offlineMutationQueueProvider);
  late StreamController<List<Purchase>> controller;
  StreamSubscription<List<Purchase>>? sourceSubscription;
  StreamSubscription<void>? queueSubscription;
  var purchases = const <Purchase>[];
  Future<void> emit() async {
    final pending = await queue.pending(businessId: businessId);
    final merged = <String, Purchase>{
      for (final purchase in purchases) purchase.purchaseId: purchase,
    };
    for (final mutation in pending.where(
      (item) => item.type == OfflineMutationType.purchaseComplete,
    )) {
      final raw = mutation.payload['summary'];
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      if (branchId != null && data['branchId'] != branchId) continue;
      final id = data['purchaseId'] as String;
      merged[id] = Purchase.fromMap(id, data);
    }
    if (!controller.isClosed) {
      final result = merged.values.toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        );
      controller.add(result);
    }
  }

  controller = StreamController<List<Purchase>>(
    onListen: () {
      sourceSubscription = source.listen((value) {
        purchases = value;
        unawaited(emit());
      }, onError: controller.addError);
      queueSubscription = queue.changes.listen((_) => unawaited(emit()));
      unawaited(emit());
    },
    onCancel: () async {
      await sourceSubscription?.cancel();
      await queueSubscription?.cancel();
    },
  );
  return controller.stream;
});

final purchaseProvider = FutureProvider.family<Purchase?, (String, String)>((
  ref,
  request,
) async {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  final pending = await ref
      .watch(offlineMutationQueueProvider)
      .pending(businessId: request.$1);
  for (final mutation in pending) {
    if (mutation.type != OfflineMutationType.purchaseComplete) continue;
    final raw = mutation.payload['summary'];
    if (raw is! Map || raw['purchaseId'] != request.$2) continue;
    final data = Map<String, dynamic>.from(raw);
    if (branchId == null || data['branchId'] == branchId) {
      return Purchase.fromMap(request.$2, data);
    }
  }
  return ref
      .watch(purchasesRepositoryProvider)
      .getPurchase(request.$1, request.$2, branchId: branchId);
});
