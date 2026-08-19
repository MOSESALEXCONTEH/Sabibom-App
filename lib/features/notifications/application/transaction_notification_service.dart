import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../data/notifications_repository.dart';
import '../data/push_notification_bootstrap.dart';

enum RecordedTransactionType { sale, expense, purchase }

class RecordedTransactionNotification {
  const RecordedTransactionNotification({
    required this.type,
    required this.entityId,
    required this.reference,
    required this.pendingSync,
    this.businessId,
    this.branchId,
  });

  final RecordedTransactionType type;
  final String entityId;
  final String reference;
  final bool pendingSync;
  final String? businessId;
  final String? branchId;

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

  AppNotificationType get appNotificationType => switch (type) {
    RecordedTransactionType.sale => AppNotificationType.saleRecorded,
    RecordedTransactionType.expense => AppNotificationType.expenseRecorded,
    RecordedTransactionType.purchase => AppNotificationType.purchaseRecorded,
  };

  String get entityType => type.name;
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

class DurableTransactionNotification {
  const DurableTransactionNotification({
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    required this.routeName,
    required this.routeParameters,
    required this.deduplicationKey,
    this.businessId,
    this.branchId,
  });

  final String userId;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? businessId;
  final String? branchId;
  final String entityType;
  final String entityId;
  final String routeName;
  final Map<String, String> routeParameters;
  final String deduplicationKey;
}

abstract interface class TransactionInAppNotificationGateway {
  Future<bool> isEnabled({required String userId, String? businessId});
  Future<void> create(DurableTransactionNotification notification);
}

class RepositoryTransactionInAppNotificationGateway
    implements TransactionInAppNotificationGateway {
  const RepositoryTransactionInAppNotificationGateway(this._repository);

  final NotificationsRepository _repository;

  @override
  Future<bool> isEnabled({required String userId, String? businessId}) async {
    final preferences = await _repository.getPreferences(
      userId: userId,
      businessId: businessId,
    );
    return preferences.inAppEnabled;
  }

  @override
  Future<void> create(DurableTransactionNotification notification) async {
    await _repository.createNotification(
      userId: notification.userId,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      businessId: notification.businessId,
      branchId: notification.branchId,
      entityType: notification.entityType,
      entityId: notification.entityId,
      routeName: notification.routeName,
      routeParameters: notification.routeParameters,
      actionLabel: 'View details',
      deduplicationKey: notification.deduplicationKey,
      sourceType: notification.entityType,
      sourceId: notification.entityId,
    );
  }
}

class InAppTransactionNotificationPresenter
    implements TransactionNotificationPresenter {
  const InAppTransactionNotificationPresenter(
    this._gateway,
    this._currentUserId,
  );

  final TransactionInAppNotificationGateway _gateway;
  final String? Function() _currentUserId;

  @override
  Future<void> present(RecordedTransactionNotification notification) async {
    final userId = _currentUserId()?.trim();
    if (userId == null || userId.isEmpty) return;
    if (!await _gateway.isEnabled(
      userId: userId,
      businessId: notification.businessId,
    )) {
      return;
    }
    final businessScope = notification.businessId?.trim().isNotEmpty == true
        ? notification.businessId!.trim()
        : '_account';
    await _gateway.create(
      DurableTransactionNotification(
        userId: userId,
        type: notification.appNotificationType,
        title: notification.title,
        body: notification.body,
        businessId: notification.businessId,
        branchId: notification.branchId,
        entityType: notification.entityType,
        entityId: notification.entityId,
        routeName: notification.routeName,
        routeParameters: <String, String>{
          notification.routeParameterName: notification.entityId,
        },
        deduplicationKey:
            '$userId:$businessScope:${notification.appNotificationType.storedValue}:${notification.entityId}',
      ),
    );
  }
}

class CompositeTransactionNotificationPresenter
    implements TransactionNotificationPresenter {
  const CompositeTransactionNotificationPresenter(this._presenters);

  final List<TransactionNotificationPresenter> _presenters;

  @override
  Future<void> present(RecordedTransactionNotification notification) async {
    for (final presenter in _presenters) {
      try {
        await presenter.present(notification);
      } catch (_) {
        // Channels are independent and notifications cannot invalidate a save.
      }
    }
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
        CompositeTransactionNotificationPresenter(
          <TransactionNotificationPresenter>[
            DeviceTransactionNotificationPresenter(
              ref.watch(pushNotificationBootstrapProvider),
            ),
            InAppTransactionNotificationPresenter(
              RepositoryTransactionInAppNotificationGateway(
                ref.watch(notificationsRepositoryProvider),
              ),
              () => FirebaseAuth.instance.currentUser?.uid,
            ),
          ],
        ),
      );
    });
