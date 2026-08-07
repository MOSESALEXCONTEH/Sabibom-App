import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import 'sabi_assistant_sheet.dart';

/// Result returned when the Ask Sabi sheet should hand off to another screen.
sealed class SabiSheetResult {
  const SabiSheetResult();
}

class SabiOpenSaleDraft extends SabiSheetResult {
  const SabiOpenSaleDraft({this.query, this.startWithVoice = false});

  final String? query;
  final bool startWithVoice;
}

class SabiOpenBusinessSetup extends SabiSheetResult {
  const SabiOpenBusinessSetup();
}

class SabiOpenExpenseDraft extends SabiSheetResult {
  const SabiOpenExpenseDraft({
    this.amountMinor,
    this.description,
    this.categoryName,
  });

  final int? amountMinor;
  final String? description;
  final String? categoryName;
}

class SabiOpenSupplierDraft extends SabiSheetResult {
  const SabiOpenSupplierDraft({this.name, this.phone});

  final String? name;
  final String? phone;
}

class SabiOpenPurchaseDraft extends SabiSheetResult {
  const SabiOpenPurchaseDraft({this.query});

  final String? query;
}

/// Single owner for opening the Sabi sale-draft route from a surviving context.
class SabiSaleDraftNavigator {
  SabiSaleDraftNavigator._();

  static var _isOpening = false;

  static bool get isOpening => _isOpening;

  /// Opens the draft under the Sales shell branch (not as a root push over the shell).
  ///
  /// Pushing a root-level route above [StatefulShellRoute] triggers a known
  /// go_router page-key collision (`!keyReservation.contains(key)`).
  static Future<void> open(
    BuildContext context, {
    String? query,
    bool startWithVoice = false,
  }) async {
    if (_isOpening || !context.mounted) return;
    _isOpening = true;
    try {
      final params = <String, String>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (startWithVoice) 'voice': '1',
      };
      final router = GoRouter.of(context);
      final currentPath = GoRouterState.of(context).uri.path;
      // Already on the draft — refresh query without stacking another page.
      if (currentPath == AppRoutes.sabiSaleDraft ||
          currentPath.endsWith('/sabi-draft')) {
        router.goNamed(
          AppRouteNames.sabiSaleDraft,
          queryParameters: params,
        );
      } else {
        // Push inside the Sales shell branch. Do not push a root-level route
        // above StatefulShellRoute — that triggers go_router's shell pageKey
        // collision (!keyReservation.contains(key)).
        // ignore: unawaited_futures
        router.pushNamed(
          AppRouteNames.sabiSaleDraft,
          queryParameters: params,
        );
      }
      await Future<void>.delayed(Duration.zero);
    } finally {
      _isOpening = false;
    }
  }
}

/// Shows Ask Sabi on the root navigator, then navigates from the parent context.
Future<void> showSabiAssistantSheet(BuildContext context) async {
  final result = await showModalBottomSheet<SabiSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const SabiAssistantSheet(),
  );
  if (!context.mounted || result == null) return;

  // Let the sheet fully dispose before GoRouter updates pages.
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return;

  switch (result) {
    case SabiOpenSaleDraft(:final query, :final startWithVoice):
      await SabiSaleDraftNavigator.open(
        context,
        query: query,
        startWithVoice: startWithVoice,
      );
    case SabiOpenBusinessSetup():
      context.push(AppRoutes.businessSetup);
    case SabiOpenExpenseDraft(
      :final amountMinor,
      :final description,
      :final categoryName,
    ):
      context.pushNamed(
        AppRouteNames.newExpense,
        queryParameters: <String, String>{
          if (amountMinor != null)
            'amount': (amountMinor / 100).toStringAsFixed(2),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (categoryName != null && categoryName.trim().isNotEmpty)
            'category': categoryName.trim(),
        },
      );
    case SabiOpenSupplierDraft(:final name, :final phone):
      context.pushNamed(
        AppRouteNames.newSupplier,
        queryParameters: <String, String>{
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
    case SabiOpenPurchaseDraft(:final query):
      context.pushNamed(
        AppRouteNames.newPurchase,
        queryParameters: <String, String>{
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
  }
}
