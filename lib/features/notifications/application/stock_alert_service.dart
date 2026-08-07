import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../../products/domain/product.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../data/notifications_repository.dart';

/// Deterministic low/out-of-stock alerts with stable deduplication keys.
/// Never call from widget build().
class StockAlertService {
  StockAlertService({
    NotificationsRepository? notifications,
    FirebaseFirestore? firestore,
    AuthenticatedApiClient? apiClient,
  }) : _notifications = notifications ?? NotificationsRepository(),
       _db = firestore ?? FirebaseFirestore.instance,
       _apiClient = apiClient ?? AuthenticatedApiClient();

  final NotificationsRepository _notifications;
  final FirebaseFirestore _db;
  final AuthenticatedApiClient _apiClient;

  static String lowStockKey(String businessId, String productId) =>
      'low_stock_${businessId}_$productId';

  static String outOfStockKey(String businessId, String productId) =>
      'out_of_stock_${businessId}_$productId';

  Future<void> evaluateProduct({
    required String businessId,
    required String businessName,
    required String branchId,
    required Product product,
  }) async {
    if (businessId.isEmpty || !product.trackStock) return;

    final lowKey = '${lowStockKey(businessId, product.id)}_$branchId';
    final outKey = '${outOfStockKey(businessId, product.id)}_$branchId';

    if (product.isOutOfStock) {
      await _notifyHolders(
        businessId: businessId,
        businessName: businessName,
        branchId: branchId,
        permission: AppPermission.viewLowStockAlerts,
        type: AppNotificationType.outOfStock,
        title: 'Out of stock',
        body: '${product.name} is out of stock.',
        product: product,
        deduplicationKey: outKey,
        priority: NotificationPriority.high,
      );
      return;
    }

    if (product.isLowStock) {
      final qtyLabel = product.quantity == product.quantity.roundToDouble()
          ? '${product.quantity.toInt()}'
          : product.quantity.toStringAsFixed(2);
      await _notifyHolders(
        businessId: businessId,
        businessName: businessName,
        branchId: branchId,
        permission: AppPermission.viewLowStockAlerts,
        type: AppNotificationType.lowStock,
        title: 'Low stock',
        body:
            '${product.name} is running low. Only $qtyLabel ${product.unit} remain.',
        product: product,
        deduplicationKey: lowKey,
        priority: NotificationPriority.normal,
      );
      return;
    }

    // Stock recovered above threshold — resolve alert cycles.
    if (product.quantity > product.lowStockThreshold) {
      await _notifications.resolveEvent(lowKey);
      await _notifications.resolveEvent(outKey);
    } else if (product.quantity > 0) {
      await _notifications.resolveEvent(outKey);
    }
  }

  Future<void> _notifyHolders({
    required String businessId,
    required String businessName,
    required String branchId,
    required AppPermission permission,
    required AppNotificationType type,
    required String title,
    required String body,
    required Product product,
    required String deduplicationKey,
    required NotificationPriority priority,
  }) async {
    final members = await _activeMembers(businessId);
    final eventKeys = <String>[];
    for (final member in members) {
      if (!member.hasPermission(permission) ||
          !member.hasBranchAccess(branchId)) {
        continue;
      }
      final eventKey = '${deduplicationKey}_${member.uid}';
      final notificationId = await _notifications.createNotification(
        userId: member.uid,
        type: type,
        title: title,
        body: body,
        businessId: businessId,
        businessName: businessName,
        branchId: branchId,
        entityType: 'product',
        entityId: product.id,
        routeName: 'productDetails',
        routeParameters: {'productId': product.id},
        actionLabel: 'Open product',
        deduplicationKey: eventKey,
        sourceType: 'product',
        sourceId: product.id,
        priority: priority,
        generatedBy: 'stock_alert_service',
      );
      if (notificationId != null) eventKeys.add(eventKey);
    }

    if (eventKeys.isEmpty) return;
    try {
      await _apiClient.postJson(
        '/api/notifications/dispatch-stock-alert',
        body: <String, dynamic>{
          'businessId': businessId,
          'branchId': branchId,
          'eventKeys': eventKeys,
        },
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {
      // Push delivery is best-effort; the durable in-app alert remains visible.
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
}
