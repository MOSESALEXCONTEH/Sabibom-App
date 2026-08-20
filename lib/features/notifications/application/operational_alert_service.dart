import '../../../core/network/authenticated_api_client.dart';

/// Requests authoritative customer-debt, supplier-credit, and large-expense
/// notification delivery after the source transaction has been persisted.
///
/// The backend re-reads the source document, thresholds, memberships,
/// permissions, preferences, quiet hours, and device tokens before creating
/// in-app records or sending push. Failures are intentionally best-effort and
/// can never fail the transaction that triggered the request.
class OperationalAlertService {
  OperationalAlertService({AuthenticatedApiClient? apiClient})
    : _apiClient = apiClient ?? AuthenticatedApiClient();

  final AuthenticatedApiClient _apiClient;

  Future<void> onCustomerCreditCreated({
    required String businessId,
    required String businessName,
    required String branchId,
    required String saleId,
    required String customerId,
    required String customerName,
    required int balanceMinor,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty ||
        branchId.isEmpty ||
        saleId.isEmpty ||
        customerId.isEmpty ||
        balanceMinor <= 0) {
      return;
    }
    await _dispatch(
      businessId: businessId,
      branchId: branchId,
      category: 'customer_debt',
      sourceId: saleId,
    );
  }

  Future<void> onSupplierCreditCreated({
    required String businessId,
    required String businessName,
    required String branchId,
    required String purchaseId,
    required String supplierId,
    required String supplierName,
    required int balanceMinor,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty ||
        branchId.isEmpty ||
        purchaseId.isEmpty ||
        supplierId.isEmpty ||
        balanceMinor <= 0) {
      return;
    }
    await _dispatch(
      businessId: businessId,
      branchId: branchId,
      category: 'supplier_credit',
      sourceId: purchaseId,
    );
  }

  Future<void> onLargeExpense({
    required String businessId,
    required String businessName,
    required String branchId,
    required String expenseId,
    required String categoryName,
    required int amountMinor,
    required String recordedBy,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty ||
        branchId.isEmpty ||
        expenseId.isEmpty ||
        amountMinor <= 0) {
      return;
    }
    await _dispatch(
      businessId: businessId,
      branchId: branchId,
      category: 'large_expense',
      sourceId: expenseId,
    );
  }

  Future<void> _dispatch({
    required String businessId,
    required String branchId,
    required String category,
    required String sourceId,
  }) async {
    try {
      await _apiClient.postJson(
        '/api/notifications/dispatch-operational-alert',
        body: <String, dynamic>{
          'businessId': businessId,
          'branchId': branchId,
          'category': category,
          'sourceId': sourceId,
        },
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {
      // Notification delivery is best-effort and must not fail saved records.
    }
  }
}
