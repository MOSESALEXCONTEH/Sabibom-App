import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/customers/application/customers_providers.dart';
import 'package:sabibom/features/customers/domain/customer.dart';

Customer _customer({
  required String id,
  required String name,
  String? phone,
  String? email,
  int balanceMinor = 0,
  CustomerStatus status = CustomerStatus.active,
}) {
  return Customer(
    id: id,
    businessId: 'biz-1',
    name: name,
    phone: phone,
    email: email,
    balanceMinor: balanceMinor,
    totalSalesMinor: 0,
    totalPaidMinor: 0,
    purchaseCount: 0,
    status: status,
  );
}

void main() {
  final customers = <Customer>[
    _customer(id: '1', name: 'Aminata Kamara', phone: '076123456'),
    _customer(
      id: '2',
      name: 'Ibrahim Sesay',
      email: 'ibrahim@example.com',
      balanceMinor: 2500,
    ),
    _customer(id: '3', name: 'Old Customer', status: CustomerStatus.archived),
  ];

  test('customers empty filter returns active customers', () {
    final result = filterCustomers(
      customers: customers,
      query: '',
      filter: CustomerListFilter.all,
    );
    expect(result.map((c) => c.id), <String>['1', '2']);
  });

  test('has balance filter', () {
    final result = filterCustomers(
      customers: customers,
      query: '',
      filter: CustomerListFilter.hasBalance,
    );
    expect(result.single.id, '2');
  });

  test('customer search by phone and email', () {
    expect(
      filterCustomers(
        customers: customers,
        query: '076',
        filter: CustomerListFilter.all,
      ).single.id,
      '1',
    );
    expect(
      filterCustomers(
        customers: customers,
        query: 'ibrahim@',
        filter: CustomerListFilter.all,
      ).single.id,
      '2',
    );
  });

  test('phone normalization strips non-digits', () {
    expect(Customer.normalizePhone('+232 (76) 123-456'), '+23276123456');
  });
}
