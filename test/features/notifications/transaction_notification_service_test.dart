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

class _RecordingGateway implements TransactionInAppNotificationGateway {
  bool enabled = true;
  bool throwOnEnabled = false;
  bool throwOnCreate = false;
  String? checkedUserId;
  String? checkedBusinessId;
  final created = <DurableTransactionNotification>[];

  @override
  Future<bool> isEnabled({required String userId, String? businessId}) async {
    checkedUserId = userId;
    checkedBusinessId = businessId;
    if (throwOnEnabled) throw StateError('preferences unavailable');
    return enabled;
  }

  @override
  Future<void> create(DurableTransactionNotification notification) async {
    created.add(notification);
    if (throwOnCreate) throw StateError('create unavailable');
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

  test(
    'composite presenter runs later channel after earlier failure',
    () async {
      final local = _RecordingPresenter()..shouldThrow = true;
      final inApp = _RecordingPresenter();
      final presenter = CompositeTransactionNotificationPresenter([
        local,
        inApp,
      ]);
      const notification = RecordedTransactionNotification(
        type: RecordedTransactionType.sale,
        entityId: 'sale-1',
        reference: 'Receipt 1',
        pendingSync: false,
      );

      await expectLater(presenter.present(notification), completes);
      expect(local.notifications, [notification]);
      expect(inApp.notifications, [notification]);
    },
  );

  test('composite presenter contains later channel failure', () async {
    final local = _RecordingPresenter();
    final inApp = _RecordingPresenter()..shouldThrow = true;
    final presenter = CompositeTransactionNotificationPresenter([local, inApp]);
    const notification = RecordedTransactionNotification(
      type: RecordedTransactionType.purchase,
      entityId: 'purchase-1',
      reference: 'Purchase 1',
      pendingSync: false,
    );

    await expectLater(presenter.present(notification), completes);
    expect(local.notifications, [notification]);
    expect(inApp.notifications, [notification]);
  });

  test(
    'durable presenter maps business scope, route, type, and dedup key',
    () async {
      final gateway = _RecordingGateway();
      final presenter = InAppTransactionNotificationPresenter(
        gateway,
        () => 'user-1',
      );
      const notification = RecordedTransactionNotification(
        type: RecordedTransactionType.expense,
        entityId: 'expense-9',
        reference: 'Fuel',
        pendingSync: false,
        businessId: 'business-2',
        branchId: 'branch-3',
      );

      await presenter.present(notification);

      expect(gateway.checkedUserId, 'user-1');
      expect(gateway.checkedBusinessId, 'business-2');
      expect(gateway.created, hasLength(1));
      final created = gateway.created.single;
      expect(created.type, AppNotificationType.expenseRecorded);
      expect(created.type.category, NotificationCategory.expenses);
      expect(created.businessId, 'business-2');
      expect(created.branchId, 'branch-3');
      expect(created.entityType, 'expense');
      expect(created.entityId, 'expense-9');
      expect(created.routeName, AppRouteNames.expenseDetails);
      expect(created.routeParameters, {'expenseId': 'expense-9'});
      expect(
        created.deduplicationKey,
        'user-1:business-2:expense_recorded:expense-9',
      );
    },
  );

  test(
    'durable presenter skips creation when in-app preference is disabled',
    () async {
      final gateway = _RecordingGateway()..enabled = false;
      final presenter = InAppTransactionNotificationPresenter(
        gateway,
        () => 'u',
      );

      await presenter.present(
        const RecordedTransactionNotification(
          type: RecordedTransactionType.sale,
          entityId: 'sale-1',
          reference: 'Receipt 1',
          pendingSync: false,
          businessId: 'business-1',
        ),
      );

      expect(gateway.created, isEmpty);
    },
  );
}
