import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Centralized navigation helpers for the Sales feature.
abstract final class SalesNavigation {
  static void openSaleDetails(BuildContext context, String? saleId) {
    final id = saleId?.trim() ?? '';
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This sale record cannot be opened.')),
      );
      return;
    }
    context.pushNamed(
      AppRouteNames.saleDetails,
      pathParameters: <String, String>{'saleId': id},
    );
  }

  static void openSaleReceipt(BuildContext context, String? saleId) {
    final id = saleId?.trim() ?? '';
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This receipt cannot be opened.')),
      );
      return;
    }
    context.pushNamed(
      AppRouteNames.saleReceipt,
      pathParameters: <String, String>{'saleId': id},
    );
  }

  static void openNewSale(BuildContext context) {
    context.pushNamed(AppRouteNames.newSale);
  }
}
