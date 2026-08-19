import '../../notifications/application/transaction_notification_service.dart';
import '../domain/sale.dart';
import 'sales_repository.dart';

class NotifyingSalesRepository implements SalesRepository {
  const NotifyingSalesRepository(this._delegate, this._notifications);

  final SalesRepository _delegate;
  final TransactionNotificationService _notifications;

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) async {
    final sale = await _delegate.completeSale(request);
    await _notifications.notify(
      RecordedTransactionNotification(
        type: RecordedTransactionType.sale,
        entityId: sale.saleId,
        reference: 'Receipt ${sale.receiptNumber}',
        pendingSync: sale.isPendingSync,
        businessId: sale.businessId,
        branchId: sale.branchId,
      ),
    );
    return sale;
  }

  @override
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId, {
    String? branchId,
  }) => _delegate.getSale(businessId, saleId, branchId: branchId);

  @override
  Future<Sale?> getSaleDocument(
    String businessId,
    String saleId, {
    String? branchId,
  }) => _delegate.getSaleDocument(businessId, saleId, branchId: branchId);

  @override
  Future<void> voidSale(
    String businessId,
    String saleId, {
    required String branchId,
    required String reason,
    String? voidedByUid,
    String? voidedByName,
  }) => _delegate.voidSale(
    businessId,
    saleId,
    branchId: branchId,
    reason: reason,
    voidedByUid: voidedByUid,
    voidedByName: voidedByName,
  );

  @override
  Stream<List<SaleHistoryItem>> watchRecentSales(
    String businessId, {
    String? branchId,
    int limit = 25,
  }) =>
      _delegate.watchRecentSales(businessId, branchId: branchId, limit: limit);
}
