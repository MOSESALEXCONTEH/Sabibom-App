import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../sales/data/sales_repository.dart';
import '../data/customers_repository.dart';
import '../data/firestore_customers_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_ledger_entry.dart';

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => FirestoreCustomersRepository(),
);

final customersListProvider = StreamProvider.family<List<Customer>, String>((
  ref,
  businessId,
) {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  return ref.watch(customersRepositoryProvider).watchCustomers(businessId, branchId: branchId);
});

final customerDetailProvider =
    FutureProvider.family<Customer?, (String, String)>((ref, request) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(customersRepositoryProvider)
          .getCustomer(request.$1, request.$2, branchId: branchId);
    });

final customerLedgerProvider =
    StreamProvider.family<List<CustomerLedgerEntry>, (String, String)>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(customersRepositoryProvider)
          .watchLedger(request.$1, request.$2, branchId: branchId);
    });

final customerSalesProvider =
    StreamProvider.family<List<SaleHistoryItem>, (String, String)>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(customersRepositoryProvider)
          .watchCustomerSales(request.$1, request.$2, branchId: branchId);
    });

List<Customer> filterCustomers({
  required List<Customer> customers,
  required String query,
  required CustomerListFilter filter,
}) {
  final normalized = query.trim().toLowerCase();
  return customers.where((customer) {
    final matchesFilter = switch (filter) {
      CustomerListFilter.all => customer.isActive,
      CustomerListFilter.active => customer.isActive,
      CustomerListFilter.hasBalance => customer.isActive && customer.hasBalance,
      CustomerListFilter.noBalance => customer.isActive && !customer.hasBalance,
      CustomerListFilter.archived => customer.isArchived,
    };
    if (!matchesFilter) return false;
    if (normalized.isEmpty) return true;
    return customer.name.toLowerCase().contains(normalized) ||
        (customer.phone ?? '').toLowerCase().contains(normalized) ||
        (customer.email ?? '').toLowerCase().contains(normalized);
  }).toList();
}
