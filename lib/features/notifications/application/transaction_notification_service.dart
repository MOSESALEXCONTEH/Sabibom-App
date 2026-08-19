import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../data/push_notification_bootstrap.dart';

enum RecordedTransactionType { sale, expense, purchase }

class RecordedTransactionNotification {
  const RecordedTransactionNotification({
    required this.type,
    required this.entityId,
    required this.reference,
    required this.pendingSync,
  });

  final RecordedTransactionType type;
  final String entityId;
  final String reference;
  final bool pendingSync;

  String get title => switch (type) {
    RecordedTransactionType.sale =>
      pendingSync ? 'Sale saved for sync' : 'Sale recorded',
    RecordedTransactionType.expense =>
      pendingSync ? 'Expense saved for sync' : 'Expense recorded',
    RecordedTransactionType.purchase =>
      pendingSync ? 'Purchase saved for sync' : 'Purchase recorded',
  };

  String get body {
    final label = reference.trim().isEmpty ? 'Transaction' : reference.trim();
    return pendingSync
        ? '$label is saved on this device and will sync when you are online.'
        : '$label was added successfully. Tap to view it.';
  }

  String get routeName => switch (type) {
    RecordedTransactionType.sale => AppRouteNames.saleDetails,
    RecordedTransactionType.expense => AppRouteNames.expenseDetails,
    RecordedTransactionType.purchase => AppRouteNames.purchaseDetails,
  };

  String get routeParameterName => switch (type) {
    RecordedTransactionType.sale => 'saleId',
    RecordedTransactionType.expense => 'expenseId',
    RecordedTransactionType.purchase => 'purchaseId',
  };
}

abstract interface class TransactionNotificationPresenter {
  Future<void> present(RecordedTransactionNotification notification);
}

class DeviceTransactionNotificationPresenter
    implements TransactionNotificationPresenter {
  DeviceTransactionNotificationPresenter(this._bootstrap);

  final PushNotificationBootstrap _bootstrap;

  @override
  Future<void> present(RecordedTransactionNotification notification) {
    return _bootstrap.showTransactionConfirmation(
      id: '${notification.type.name}:${notification.entityId}'.hashCode,
      title: notification.title,
      body: notification.body,
      routeName: notification.routeName,
      routeParameterName: notification.routeParameterName,
      routeParameterValue: notification.entityId,
    );
  }
}

class TransactionNotificationService {
  const TransactionNotificationService(this._presenter);

  final TransactionNotificationPresenter _presenter;

  Future<void> notify(RecordedTransactionNotification notification) async {
    try {
      await _presenter.present(notification);
    } catch (_) {
      // Notification delivery is best-effort and cannot invalidate a save.
    }
  }
}

final transactionNotificationServiceProvider =
    Provider<TransactionNotificationService>((ref) {
      return TransactionNotificationService(
        DeviceTransactionNotificationPresenter(
          ref.watch(pushNotificationBootstrapProvider),
        ),
      );
    });
