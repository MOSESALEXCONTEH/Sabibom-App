// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../team/presentation/team_widgets.dart';
import '../domain/app_notification.dart';

Future<void> openNotificationRoute(
  BuildContext context,
  AppNotification n,
) async {
  final routeName = n.routeName;
  if (n.sourceType == 'platform_announcement') {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.campaign_outlined),
        title: Text(n.title),
        content: SingleChildScrollView(child: Text(n.message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    return;
  }
  if (NotificationRouteAllowlist.isAllowed(routeName)) {
    try {
      final pathParameters = {
        for (final e in n.routeParameters.entries)
          if (e.key == 'productId' ||
              e.key == 'customerId' ||
              e.key == 'supplierId' ||
              e.key == 'expenseId' ||
              e.key == 'saleId' ||
              e.key == 'approvalId' ||
              e.key == 'dateKey' ||
              e.key == 'weekKey')
            e.key: e.value,
      };
      final queryParameters = {
        for (final e in n.routeParameters.entries)
          if (e.key != 'productId' &&
              e.key != 'customerId' &&
              e.key != 'supplierId' &&
              e.key != 'expenseId' &&
              e.key != 'saleId' &&
              e.key != 'approvalId' &&
              e.key != 'dateKey' &&
              e.key != 'weekKey')
            e.key: e.value,
      };
      const shellRouteNames = {
        AppRouteNames.products,
        AppRouteNames.productDetails,
        AppRouteNames.customers,
        AppRouteNames.customerDetails,
        AppRouteNames.suppliers,
        AppRouteNames.supplierDetails,
      };
      if (shellRouteNames.contains(routeName)) {
        context.goNamed(
          routeName!,
          pathParameters: pathParameters,
          queryParameters: queryParameters,
        );
        return;
      }
      await context.pushNamed(
        routeName!,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
      );
      return;
    } catch (_) {
      // Fall through to type-based routing.
    }
  }

  if (n.type == AppNotificationType.invitationReceived) {
    context.pushNamed(AppRouteNames.invite);
    return;
  }
  if (n.type == AppNotificationType.approvalRequested ||
      n.type == AppNotificationType.approvalApproved ||
      n.type == AppNotificationType.approvalRejected ||
      n.type == AppNotificationType.approvalExpired) {
    if (n.entityId != null && n.entityId!.isNotEmpty) {
      context.pushNamed(
        AppRouteNames.approvalDetails,
        pathParameters: {'approvalId': n.entityId!},
      );
    } else {
      context.pushNamed(AppRouteNames.approvals);
    }
    return;
  }
  if (n.type == AppNotificationType.roleChanged ||
      n.type == AppNotificationType.permissionChanged ||
      n.type == AppNotificationType.membershipDisabled ||
      n.type == AppNotificationType.membershipRestored) {
    context.pushNamed(AppRouteNames.myRole);
    return;
  }
  if (n.type == AppNotificationType.lowStock ||
      n.type == AppNotificationType.outOfStock ||
      n.type == AppNotificationType.stockReplenished ||
      n.type == AppNotificationType.productExpiryApproaching ||
      n.type == AppNotificationType.productExpiresToday ||
      n.type == AppNotificationType.productExpired ||
      n.type == AppNotificationType.productExpiryUnknown ||
      n.type == AppNotificationType.expiredStockDisposed) {
    if (n.entityId != null && n.entityId!.isNotEmpty) {
      context.pushNamed(
        AppRouteNames.productDetails,
        pathParameters: {'productId': n.entityId!},
      );
    } else if (n.type == AppNotificationType.productExpiryApproaching ||
        n.type == AppNotificationType.productExpiresToday ||
        n.type == AppNotificationType.productExpired ||
        n.type == AppNotificationType.productExpiryUnknown) {
      context.pushNamed(AppRouteNames.reportProductExpiry);
    } else {
      context.pushNamed(AppRouteNames.products);
    }
    return;
  }
  if (n.type == AppNotificationType.customerCreditCreated ||
      n.type == AppNotificationType.customerDebtOverdue ||
      n.type == AppNotificationType.customerLargeBalance) {
    if (n.entityId != null && n.entityId!.isNotEmpty) {
      context.pushNamed(
        AppRouteNames.customerDetails,
        pathParameters: {'customerId': n.entityId!},
      );
    } else {
      context.pushNamed(AppRouteNames.customers);
    }
    return;
  }
  if (n.type == AppNotificationType.supplierCreditCreated ||
      n.type == AppNotificationType.supplierPaymentDue ||
      n.type == AppNotificationType.supplierBalanceOverdue) {
    if (n.entityId != null && n.entityId!.isNotEmpty) {
      context.pushNamed(
        AppRouteNames.supplierDetails,
        pathParameters: {'supplierId': n.entityId!},
      );
    } else {
      context.pushNamed(AppRouteNames.suppliers);
    }
    return;
  }
  if (n.type == AppNotificationType.largeExpense) {
    if (n.entityId != null && n.entityId!.isNotEmpty) {
      context.pushNamed(
        AppRouteNames.expenseDetails,
        pathParameters: {'expenseId': n.entityId!},
      );
    } else {
      context.pushNamed(AppRouteNames.expenses);
    }
    return;
  }
  if (n.type == AppNotificationType.dailySummaryReady) {
    final dateKey =
        n.routeParameters['dateKey'] ??
        n.entityId ??
        DateTime.now().toIso8601String().substring(0, 10);
    context.pushNamed(
      AppRouteNames.dailySummary,
      pathParameters: {'dateKey': dateKey},
    );
    return;
  }
  if (n.type == AppNotificationType.weeklyReportReady) {
    final weekKey = n.routeParameters['weekKey'] ?? n.entityId ?? 'current';
    context.pushNamed(
      AppRouteNames.weeklyReport,
      pathParameters: {'weekKey': weekKey},
    );
    return;
  }
  if (n.type == AppNotificationType.endOfDayIncomplete ||
      n.type == AppNotificationType.endOfDayShortage ||
      n.type == AppNotificationType.endOfDaySurplus) {
    final dateKey =
        n.routeParameters['dateKey'] ??
        n.entityId ??
        DateTime.now().toIso8601String().substring(0, 10);
    context.pushNamed(
      AppRouteNames.endOfDay,
      pathParameters: {'dateKey': dateKey},
    );
    return;
  }
  if (n.entityType == 'sale' && n.entityId != null) {
    context.pushNamed(
      AppRouteNames.saleDetails,
      pathParameters: {'saleId': n.entityId!},
    );
  }
}

void showNotificationAccessDenied(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const AccessDeniedScreen(
        message: 'You do not have permission to view this alert.',
      ),
    ),
  );
}
