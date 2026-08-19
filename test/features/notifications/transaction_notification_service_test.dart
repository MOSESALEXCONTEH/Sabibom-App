import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/router.dart';
import 'package:sabibom/features/notifications/application/transaction_notification_service.dart';
import 'package:sabibom/features/notifications/domain/app_notification.dart';

class _RecordingPresenter implements TransactionNotificationPresenter {
  final notifications = <RecordedTransactionNotification>[];
  var shouldThrow = false;

  @override
  Future<void> present(RecordedTransactionNotification notification) async {
    notifications.add(notification);
    if (shouldThrow) throw StateError('notifications unavailable');
  }
}

void main() {
  test('transaction types deep-link to their detail screens', () {
    const cases = <(RecordedTransactionType, String, String)>[
      (RecordedTransactionType.sale, AppRouteNames.saleDetails, 'saleId'),
      (
        RecordedTransactionType.expense,
        AppRouteNames.expenseDetails,
        'expenseId',
      ),
      (
        RecordedTransactionType.purchase,
        AppRouteNames.purchaseDetails,
        'purchaseId',
      ),
    ];

    for (final entry in cases) {
      final notification = RecordedTransactionNotification(
        type: entry.$1,
        entityId: 'entity-1',
        reference: 'Reference 1',
        pendingSync: false,
      );
      expect(notification.routeName, entry.$2);
      expect(notification.routeParameterName, entry.$3);
      expect(
        NotificationRouteAllowlist.isAllowed(notification.routeName),
        isTrue,
      );
      expect(notification.body, contains('added successfully'));
    }
  });

  test('offline notification clearly reports pending synchronization', () {
    const notification = RecordedTransactionNotification(
      type: RecordedTransactionType.sale,
      entityId: 'sale-1',
      reference: 'Receipt Pending 1234',
      pendingSync: true,
    );

    expect(notification.title, 'Sale saved for sync');
    expect(notification.body, contains('will sync when you are online'));
  });

  test(
    'notification failure does not escape after a successful save',
    () async {
      final presenter = _RecordingPresenter()..shouldThrow = true;
      final service = TransactionNotificationService(presenter);
      const notification = RecordedTransactionNotification(
        type: RecordedTransactionType.expense,
        entityId: 'expense-1',
        reference: 'Transport',
        pendingSync: false,
      );

      await expectLater(service.notify(notification), completes);
      expect(presenter.notifications, contains(notification));
    },
  );
}
