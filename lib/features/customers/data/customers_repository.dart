import '../../sales/data/sales_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_ledger_entry.dart';

class CustomerDraft {
  const CustomerDraft({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.usesWhatsApp = false,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool usesWhatsApp;
}

class CustomerPaymentRequest {
  const CustomerPaymentRequest({
    required this.customerId,
    required this.amountMinor,
    required this.paymentMethod,
    this.reference,
    this.note,
  });

  final String customerId;
  final int amountMinor;
  final String paymentMethod;
  final String? reference;
  final String? note;
}

class DuplicateCustomerException implements Exception {
  const DuplicateCustomerException(this.existing);

  final Customer existing;
}

abstract interface class CustomersRepository {
  Stream<List<Customer>> watchCustomers(String businessId, {String? branchId});
  Future<Customer?> getCustomer(String businessId, String customerId, {String? branchId});
  Future<Customer?> findByNormalizedPhone(String businessId, String phone, {String? branchId});
  Future<String> createCustomer(
    String businessId,
    CustomerDraft draft, {
    bool allowDuplicatePhone = false,
    String? branchId,
  });
  Future<void> updateCustomer(
    String businessId,
    String customerId,
    CustomerDraft draft, {
    String? branchId,
  });
  Future<void> setCustomerStatus(
    String businessId,
    String customerId,
    CustomerStatus status, {
    String? branchId,
  });
  Future<void> recordPayment(
    String businessId,
    CustomerPaymentRequest request, {
    String? branchId,
  });
  Stream<List<CustomerLedgerEntry>> watchLedger(
    String businessId,
    String customerId, {
    String? branchId,
    int limit = 25,
  });
  Stream<List<SaleHistoryItem>> watchCustomerSales(
    String businessId,
    String customerId, {
    String? branchId,
    int limit = 20,
  });
}

class CustomerException implements Exception {
  const CustomerException(this.code, {this.message});

  final String code;
  final String? message;

  String get friendlyMessage =>
      message ??
      switch (code) {
        'permission-denied' =>
          'You do not have permission to access this business information.',
        'unavailable' =>
          'This information is temporarily unavailable. Please try again.',
        'not-found' =>
          'This record could not be found. It may have been removed or archived.',
        'failed-precondition' => 'This payment cannot be completed.',
        'unauthenticated' => 'Your session expired. Please sign in again.',
        _ => 'Something went wrong. Please try again.',
      };
}
