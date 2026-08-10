import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/application/dashboard_providers.dart';
import '../domain/business_operating_model.dart';

class BusinessCapabilities {
  const BusinessCapabilities(this.operatingModel);

  final BusinessOperatingModel operatingModel;

  bool get managesInventory => operatingModel != BusinessOperatingModel.service;
  bool get managesPurchases => managesInventory;
  bool get offersServices => operatingModel != BusinessOperatingModel.product;
}

class BusinessTerminology {
  const BusinessTerminology({
    required this.sales,
    required this.sale,
    required this.products,
    required this.product,
    required this.customers,
    required this.customer,
  });

  const BusinessTerminology.product()
    : sales = 'Sales',
      sale = 'Sale',
      products = 'Products',
      product = 'Product',
      customers = 'Customers',
      customer = 'Customer';

  factory BusinessTerminology.forModel(BusinessOperatingModel model) {
    if (model == BusinessOperatingModel.service) {
      return const BusinessTerminology(
        sales: 'Income',
        sale: 'Transaction',
        products: 'Services',
        product: 'Service',
        customers: 'Clients',
        customer: 'Client',
      );
    }
    if (model == BusinessOperatingModel.hybrid) {
      return const BusinessTerminology(
        sales: 'Sales',
        sale: 'Sale',
        products: 'Catalog',
        product: 'Item',
        customers: 'Customers',
        customer: 'Customer',
      );
    }
    return const BusinessTerminology.product();
  }

  final String sales;
  final String sale;
  final String products;
  final String product;
  final String customers;
  final String customer;
}

final currentBusinessOperatingModelProvider = Provider<BusinessOperatingModel>((
  ref,
) {
  final active = ref.watch(activeBusinessProvider).asData?.value;
  return switch (active) {
    ActiveBusinessData(:final business) => business.operatingModel,
    _ => BusinessOperatingModel.product,
  };
});

final currentBusinessCapabilitiesProvider = Provider<BusinessCapabilities>((
  ref,
) {
  return BusinessCapabilities(ref.watch(currentBusinessOperatingModelProvider));
});

final currentBusinessTerminologyProvider = Provider<BusinessTerminology>((ref) {
  return BusinessTerminology.forModel(
    ref.watch(currentBusinessOperatingModelProvider),
  );
});
