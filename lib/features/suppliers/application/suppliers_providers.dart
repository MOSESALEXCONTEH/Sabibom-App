import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/suppliers_repository.dart';
import '../domain/supplier.dart';

final suppliersRepositoryProvider = Provider<SuppliersRepository>(
  (ref) => FirestoreSuppliersRepository(),
);

final suppliersListProvider = StreamProvider.family<List<Supplier>, String>((
  ref,
  businessId,
) {
  return ref.watch(suppliersRepositoryProvider).watchSuppliers(businessId);
});

final supplierDetailProvider =
    FutureProvider.family<Supplier?, (String, String)>((ref, request) {
      return ref
          .watch(suppliersRepositoryProvider)
          .getSupplier(request.$1, request.$2);
    });

final supplierLedgerProvider =
    StreamProvider.family<List<SupplierLedgerEntry>, (String, String)>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(suppliersRepositoryProvider)
          .watchLedger(request.$1, request.$2, branchId: branchId);
    });

List<Supplier> filterSuppliers({
  required List<Supplier> suppliers,
  required String query,
  required SupplierListFilter filter,
}) {
  final normalized = query.trim().toLowerCase();
  return suppliers.where((supplier) {
    final matchesFilter = switch (filter) {
      SupplierListFilter.all => supplier.isActive,
      SupplierListFilter.active => supplier.isActive,
      SupplierListFilter.hasBalance => supplier.isActive && supplier.hasBalance,
      SupplierListFilter.archived => supplier.isArchived,
    };
    if (!matchesFilter) return false;
    if (normalized.isEmpty) return true;
    return supplier.name.toLowerCase().contains(normalized) ||
        (supplier.contactPerson ?? '').toLowerCase().contains(normalized) ||
        (supplier.phone ?? '').toLowerCase().contains(normalized) ||
        (supplier.email ?? '').toLowerCase().contains(normalized);
  }).toList();
}
