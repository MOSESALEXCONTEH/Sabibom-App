import '../../business_setup/domain/business.dart';
import '../application/sale_cart_controller.dart';
import '../domain/sale_models.dart';

class CompleteSaleRequest {
  const CompleteSaleRequest({
    required this.business,
    required this.cart,
    required this.saleId,
    required this.cashierName,
  });

  final Business business;
  final SaleCartState cart;
  final String saleId;
  final String? cashierName;
}

class CompletedSale {
  const CompletedSale({
    required this.saleId,
    required this.receiptNumber,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    required this.changeMinor,
    required this.paymentMethod,
  });

  final String saleId;
  final String receiptNumber;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final int changeMinor;
  final PaymentMethod paymentMethod;
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

  factory SaleHistoryItem.fromFirestore(String id, Map<String, dynamic> data) => SaleHistoryItem(
    saleId: id,
    receiptNumber: data['receiptNumber'] as String? ?? id,
    customerName: data['customerName'] as String? ?? 'Walk-in Customer',
    totalMinor: (data['totalMinor'] as num?)?.toInt() ?? moneyToMinor(data['total']),
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
  );

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
  Stream<List<SaleHistoryItem>> watchRecentSales(String businessId, {int limit = 25});
  Future<Map<String, dynamic>?> getSale(String businessId, String saleId);
}