import '../../business_setup/domain/business.dart';
import '../application/sale_cart_controller.dart';
import '../domain/sale.dart';
import '../domain/sale_models.dart';

class CompleteSaleRequest {
  const CompleteSaleRequest({
    required this.business,
    required this.cart,
    required this.saleId,
    required this.cashierName,
    required this.branchId,
    required this.branchNameSnapshot,
    required this.branchCodeSnapshot,
    this.queueWhenOffline = false,
  });

  final Business business;
  final SaleCartState cart;
  final String saleId;
  final String? cashierName;
  final String branchId;
  final String branchNameSnapshot;
  final String branchCodeSnapshot;
  final bool queueWhenOffline;
}

class CompletedSale {
  const CompletedSale({
    required this.saleId,
    required this.businessId,
    required this.branchId,
    required this.branchNameSnapshot,
    required this.branchCodeSnapshot,
    required this.receiptNumber,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    required this.changeMinor,
    required this.paymentMethod,
    this.isPendingSync = false,
  });

  final String saleId;
  final String businessId;
  final String branchId;
  final String branchNameSnapshot;
  final String branchCodeSnapshot;
  final String receiptNumber;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final int changeMinor;
  final PaymentMethod paymentMethod;
  final bool isPendingSync;
}

class SaleHistoryItem {
  const SaleHistoryItem({
    required this.saleId,
    required this.receiptNumber,
    required this.customerName,
    required this.totalMinor,
    required this.currencyCode,
    required this.currencySymbol,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.saleStatus,
    this.createdAt,
  });

  factory SaleHistoryItem.fromFirestore(String id, Map<String, dynamic> data) {
    final storedId = (data['saleId'] as String?)?.trim();
    final resolvedId = id.trim().isNotEmpty ? id : (storedId ?? '');
    return SaleHistoryItem(
      saleId: resolvedId,
      receiptNumber: data['receiptNumber'] as String? ?? resolvedId,
      customerName: data['customerName'] as String? ?? 'Walk-in Customer',
      totalMinor:
          (data['totalMinor'] as num?)?.toInt() ?? moneyToMinor(data['total']),
      currencyCode: data['currencyCode'] as String? ?? 'SLE',
      currencySymbol: data['currencySymbol'] as String? ?? 'Le',
      paymentMethod: PaymentMethod.values.firstWhere(
        (method) => method.storedValue == data['paymentMethod'],
        orElse: () => PaymentMethod.cash,
      ),
      paymentStatus: PaymentStatus.values.firstWhere(
        (status) => status.name == data['paymentStatus'],
        orElse: () => PaymentStatus.paid,
      ),
      saleStatus: SaleStatus.values.firstWhere(
        (status) => status.name == (data['saleStatus'] ?? data['status']),
        orElse: () => SaleStatus.completed,
      ),
      createdAt: _readDate(data['createdAt']),
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    try {
      // Timestamp from cloud_firestore without importing the package here.
      return (value as dynamic).toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }

  final String saleId;
  final String receiptNumber;
  final String customerName;
  final int totalMinor;
  final String currencyCode;
  final String currencySymbol;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final SaleStatus saleStatus;
  final DateTime? createdAt;
}

abstract interface class SalesRepository {
  Future<CompletedSale> completeSale(CompleteSaleRequest request);
  Future<void> voidSale(
    String businessId,
    String saleId, {
    required String branchId,
    required String reason,
    String? voidedByUid,
    String? voidedByName,
  });
  Stream<List<SaleHistoryItem>> watchRecentSales(
    String businessId, {
    String? branchId,
    int limit = 25,
  });
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId, {
    String? branchId,
  });
  Future<Sale?> getSaleDocument(
    String businessId,
    String saleId, {
    String? branchId,
  });
}
