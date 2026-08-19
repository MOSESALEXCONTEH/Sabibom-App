import '../../notifications/application/transaction_notification_service.dart';
import '../domain/purchase.dart';
import 'purchases_repository.dart';

class NotifyingPurchasesRepository implements PurchasesRepository {
  const NotifyingPurchasesRepository(this._delegate, this._notifications);

  final PurchasesRepository _delegate;
  final TransactionNotificationService _notifications;

  @override
  Future<Purchase> completePurchase(CompletePurchaseRequest request) async {
    final purchase = await _delegate.completePurchase(request);
    await _notifications.notify(
      RecordedTransactionNotification(
        type: RecordedTransactionType.purchase,
        entityId: purchase.purchaseId,
        reference: 'Purchase ${purchase.purchaseNumber}',
        pendingSync: request.queueWhenOffline,
        businessId: purchase.businessId,
        branchId: purchase.branchId,
      ),
    );
    return purchase;
  }

  @override
  Future<void> createPurchaseReturn(
    CreatePurchaseReturnRequest request, {
    String? branchId,
  }) => _delegate.createPurchaseReturn(request, branchId: branchId);

  @override
  Future<Purchase?> getPurchase(
    String businessId,
    String purchaseId, {
    String? branchId,
  }) => _delegate.getPurchase(businessId, purchaseId, branchId: branchId);

  @override
  Future<void> voidPurchase(
    String businessId,
    String purchaseId, {
    required String reason,
    String? branchId,
  }) => _delegate.voidPurchase(
    businessId,
    purchaseId,
    reason: reason,
    branchId: branchId,
  );

  @override
  Stream<List<Purchase>> watchPurchases(
    String businessId, {
    String? branchId,
  }) => _delegate.watchPurchases(businessId, branchId: branchId);
}
