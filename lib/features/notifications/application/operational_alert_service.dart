import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../data/notifications_repository.dart';

/// Customer debt, supplier debt, and large-expense alerts with dedupe keys.
class OperationalAlertService {
  OperationalAlertService({
    NotificationsRepository? notifications,
    FirebaseFirestore? firestore,
  }) : _notifications = notifications ?? NotificationsRepository(),
       _db = firestore ?? FirebaseFirestore.instance;

  final NotificationsRepository _notifications;
  final FirebaseFirestore _db;

  Future<void> onCustomerCreditCreated({
    required String businessId,
    required String businessName,
    required String branchId,
    required String customerId,
    required String customerName,
    required int balanceMinor,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty || customerId.isEmpty || balanceMinor <= 0) return;
    final amount = formatCurrency(balanceMinor / 100, symbol: currencySymbol);
    await _notify(
      businessId: businessId,
      businessName: businessName,
      branchId: branchId,
      permission: AppPermission.viewCustomerDebtAlerts,
      type: AppNotificationType.customerCreditCreated,
      title: 'Customer credit',
      body: '$customerName owes $amount.',
      entityType: 'customer',
      entityId: customerId,
      routeName: 'customerDetails',
      routeParameters: {'customerId': customerId},
      deduplicationKey:
          'customer_credit_${businessId}_${customerId}_${_dayKey()}',
      prefsGate: (p) => p.customerDebtEnabled,
      thresholdGate: (p) => balanceMinor >= p.customerDebtMinimumMinor,
    );
  }

  Future<void> onCustomerDebtResolved({
    required String businessId,
    required String customerId,
  }) async {
    await _notifications.resolveEvent(
      'customer_debt_${businessId}_$customerId',
    );
  }

  Future<void> onSupplierCreditCreated({
    required String businessId,
    required String businessName,
    required String branchId,
    required String supplierId,
    required String supplierName,
    required int balanceMinor,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty || supplierId.isEmpty || balanceMinor <= 0) return;
    final amount = formatCurrency(balanceMinor / 100, symbol: currencySymbol);
    await _notify(
      businessId: businessId,
      businessName: businessName,
      branchId: branchId,
      permission: AppPermission.viewSupplierPaymentAlerts,
      type: AppNotificationType.supplierCreditCreated,
      title: 'Supplier balance',
      body: '$supplierName is owed $amount.',
      entityType: 'supplier',
      entityId: supplierId,
      routeName: 'supplierDetails',
      routeParameters: {'supplierId': supplierId},
      deduplicationKey:
          'supplier_credit_${businessId}_${supplierId}_${_dayKey()}',
      prefsGate: (p) => p.supplierPaymentEnabled,
      thresholdGate: (p) => balanceMinor >= p.supplierDebtMinimumMinor,
    );
  }

  Future<void> onLargeExpense({
    required String businessId,
    required String businessName,
    required String branchId,
    required String expenseId,
    required String categoryName,
    required int amountMinor,
    required String recordedBy,
    String currencySymbol = 'Le',
  }) async {
    if (businessId.isEmpty || expenseId.isEmpty || amountMinor <= 0) return;
    final amount = formatCurrency(amountMinor / 100, symbol: currencySymbol);
    await _notify(
      businessId: businessId,
      businessName: businessName,
      branchId: branchId,
      permission: AppPermission.viewExpenses,
      type: AppNotificationType.largeExpense,
      title: 'Large expense',
      body: 'A large expense of $amount was recorded for $categoryName.',
      entityType: 'expense',
      entityId: expenseId,
      routeName: 'expenseDetails',
      routeParameters: {'expenseId': expenseId},
      deduplicationKey: 'large_expense_${businessId}_$expenseId',
      prefsGate: (p) => p.largeExpenseEnabled,
      thresholdGate: (p) => amountMinor >= p.largeExpenseThresholdMinor,
      data: {'recordedBy': recordedBy},
    );
  }

  Future<void> _notify({
    required String businessId,
    required String businessName,
    required String branchId,
    required AppPermission permission,
    required AppNotificationType type,
    required String title,
    required String body,
    required String entityType,
    required String entityId,
    required String routeName,
    required Map<String, String> routeParameters,
    required String deduplicationKey,
    required bool Function(NotificationPreferences) prefsGate,
    required bool Function(NotificationPreferences) thresholdGate,
    Map<String, Object?>? data,
  }) async {
    final members = await _activeMembers(businessId);
    for (final member in members) {
      if (!member.hasPermission(permission)) continue;
      final prefs = await _notifications.getPreferences(
        userId: member.uid,
        businessId: businessId,
      );
      if (!prefs.inAppEnabled || !prefsGate(prefs) || !thresholdGate(prefs)) {
        continue;
      }
      await _notifications.createNotification(
        userId: member.uid,
        type: type,
        title: title,
        body: body,
        businessId: businessId,
        businessName: businessName,
        branchId: branchId,
        entityType: entityType,
        entityId: entityId,
        routeName: routeName,
        routeParameters: routeParameters,
        deduplicationKey: '${deduplicationKey}_${member.uid}',
        sourceType: entityType,
        sourceId: entityId,
        generatedBy: 'operational_alert_service',
        data: data,
      );
    }
  }

  Future<List<BusinessMembership>> _activeMembers(String businessId) async {
    final snap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs
        .map((d) => BusinessMembership.fromMap(d.id, businessId, d.data()))
        .toList(growable: false);
  }

  String _dayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}
