import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../branches/domain/business_branch.dart';
import '../../products/data/firestore_products_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../data/notifications_repository.dart';
import '../domain/attention_summary.dart';

/// Builds a deterministic attention summary from verified Firestore data.
class AttentionSummaryService {
  AttentionSummaryService({
    FirebaseFirestore? firestore,
    NotificationsRepository? notifications,
    ProductsRepository? products,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _notifications = notifications ?? NotificationsRepository(),
       _products =
           products ?? FirestoreProductsRepository(firestore: firestore);

  final FirebaseFirestore _db;
  final NotificationsRepository _notifications;
  final ProductsRepository _products;

  Future<AttentionSummary> build({
    required String businessId,
    required String businessName,
    String? branchId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (businessId.isEmpty || uid == null) {
      return AttentionSummary(
        businessId: businessId,
        businessName: businessName,
        generatedAt: DateTime.now(),
      );
    }

    final memberSnap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('members')
        .doc(uid)
        .get();
    if (!memberSnap.exists || memberSnap.data() == null) {
      return AttentionSummary(
        businessId: businessId,
        businessName: businessName,
        generatedAt: DateTime.now(),
      );
    }
    final membership = BusinessMembership.fromMap(
      uid,
      businessId,
      memberSnap.data()!,
    );

    bool can(AppPermission p) => membership.hasPermission(p);

    final items = <AttentionItem>[];
    var lowStock = 0;
    var outOfStock = 0;
    var expiringSoon = 0;
    var expired = 0;
    var pendingApprovals = 0;
    var overdueCustomers = 0;
    var customerOutstanding = 0;
    var overdueSuppliers = 0;
    var supplierOutstanding = 0;

    final unread = await _notifications.watchUnreadCount(uid).first;

    if (can(AppPermission.viewLowStockAlerts) ||
        can(AppPermission.viewProducts) ||
        can(AppPermission.viewProductExpiry)) {
      final products = await _products
          .watchProducts(businessId, branchId: branchId)
          .first;
      final branchProductIds = await _branchProductIds(
        businessId: businessId,
        branchId: branchId,
      );
      for (final p
          in products
              .where(
                (product) =>
                    product.isActive &&
                    (branchProductIds == null ||
                        branchProductIds.contains(product.id)),
              )
              .take(200)) {
        if (can(AppPermission.viewProductExpiry) && p.tracksExpiry) {
          if (p.expiredQuantity > 0 ||
              p.expiryStatus == ProductExpiryStatus.expired) {
            expired++;
          } else if (p.expiryStatus == ProductExpiryStatus.expiringSoon ||
              p.expiryStatus == ProductExpiryStatus.expiresToday ||
              p.expiringQuantity > 0) {
            expiringSoon++;
          }
        }
        if (!p.trackStock) continue;
        if (p.isOutOfStock) {
          outOfStock++;
          items.add(
            AttentionItem(
              id: 'oos_${p.id}',
              title: '${p.name} is out of stock',
              subtitle: 'Restock this product soon.',
              priority: 'high',
              routeName: 'productDetails',
              routeParameters: {'productId': p.id},
              iconName: 'inventory',
            ),
          );
        } else if (p.isLowStock) {
          lowStock++;
        }
      }
      if (expired > 0 && can(AppPermission.viewProductExpiry)) {
        items.add(
          AttentionItem(
            id: 'expired_summary',
            title: '$expired products have expired stock',
            subtitle: 'Review and dispose expired batches.',
            priority: 'urgent',
            routeName: 'reportProductExpiry',
            iconName: 'event_busy',
          ),
        );
      }
      if (expiringSoon > 0 && can(AppPermission.viewProductExpiry)) {
        items.add(
          AttentionItem(
            id: 'expiring_summary',
            title: '$expiringSoon products are expiring soon',
            subtitle: 'Sell or restock before they expire.',
            priority: 'high',
            routeName: 'reportProductExpiry',
            iconName: 'schedule',
          ),
        );
      }
      if (lowStock > 0) {
        items.add(
          AttentionItem(
            id: 'low_stock_summary',
            title: '$lowStock products are low in stock',
            subtitle: 'Review inventory before you sell out.',
            priority: 'normal',
            routeName: 'products',
            iconName: 'inventory',
          ),
        );
      }
    }

    if (can(AppPermission.viewCustomerDebtAlerts) ||
        can(AppPermission.viewCustomerBalance)) {
      final customers = await _db
          .collection('businesses')
          .doc(businessId)
          .collection('customers')
          .where('balanceMinor', isGreaterThan: 0)
          .orderBy('balanceMinor', descending: true)
          .limit(20)
          .get();
      for (final doc in customers.docs) {
        if (!matchesBranchScope(doc.data(), branchId)) continue;
        final bal = (doc.data()['balanceMinor'] as num?)?.toInt() ?? 0;
        if (bal <= 0) continue;
        overdueCustomers++;
        customerOutstanding += bal;
        if (overdueCustomers <= 2) {
          final name = (doc.data()['name'] as String?) ?? 'Customer';
          items.add(
            AttentionItem(
              id: 'cust_${doc.id}',
              title: '$name owes a balance',
              subtitle: 'Open customer to review or record payment.',
              priority: bal >= 100000 ? 'high' : 'normal',
              routeName: 'customerDetails',
              routeParameters: {'customerId': doc.id},
              iconName: 'person',
            ),
          );
        }
      }
    }

    if (can(AppPermission.viewSupplierPaymentAlerts) ||
        can(AppPermission.viewSupplierBalance)) {
      final suppliers = await _db
          .collection('businesses')
          .doc(businessId)
          .collection('suppliers')
          .where('balanceMinor', isGreaterThan: 0)
          .orderBy('balanceMinor', descending: true)
          .limit(20)
          .get();
      for (final doc in suppliers.docs) {
        if (!matchesBranchScope(doc.data(), branchId)) continue;
        final bal = (doc.data()['balanceMinor'] as num?)?.toInt() ?? 0;
        if (bal <= 0) continue;
        overdueSuppliers++;
        supplierOutstanding += bal;
        if (overdueSuppliers <= 2) {
          final name = (doc.data()['name'] as String?) ?? 'Supplier';
          items.add(
            AttentionItem(
              id: 'sup_${doc.id}',
              title: '$name is owed money',
              subtitle: 'Review supplier balance or record a payment.',
              priority: bal >= 200000 ? 'high' : 'normal',
              routeName: 'supplierDetails',
              routeParameters: {'supplierId': doc.id},
              iconName: 'local_shipping',
            ),
          );
        }
      }
    }

    if (can(AppPermission.viewApprovalNotifications) ||
        can(AppPermission.approveSensitiveActions)) {
      final approvals = await _db
          .collection('businesses')
          .doc(businessId)
          .collection('approval_requests')
          .where('status', isEqualTo: 'pending')
          .limit(20)
          .get();
      pendingApprovals = approvals.docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .length;
      if (pendingApprovals > 0) {
        items.add(
          AttentionItem(
            id: 'approvals_pending',
            title:
                '$pendingApprovals pending approval${pendingApprovals == 1 ? '' : 's'}',
            subtitle: 'Review requests waiting for a decision.',
            priority: 'high',
            routeName: 'approvals',
            iconName: 'fact_check',
          ),
        );
      }
    }

    int weight(String p) => switch (p) {
      'urgent' => 0,
      'high' => 1,
      'normal' => 2,
      _ => 3,
    };
    items.sort((a, b) => weight(a.priority).compareTo(weight(b.priority)));

    return AttentionSummary(
      businessId: businessId,
      businessName: businessName,
      generatedAt: DateTime.now(),
      unreadNotificationCount: unread,
      urgentNotificationCount: items
          .where((i) => i.priority == 'urgent')
          .length,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
      overdueCustomerCount: overdueCustomers,
      customerOutstandingMinor: customerOutstanding,
      overdueSupplierCount: overdueSuppliers,
      supplierOutstandingMinor: supplierOutstanding,
      pendingApprovalCount: pendingApprovals,
      attentionItems: List<AttentionItem>.unmodifiable(items),
      topAttentionItems: items.take(5).toList(growable: false),
    );
  }

  Future<Set<String>?> _branchProductIds({
    required String businessId,
    required String? branchId,
  }) async {
    final normalized = normalizeBranchId(branchId);
    // All Branches aggregates every inventory row. Main also owns legacy
    // product-level stock that predates branch inventory documents.
    if (normalized == null || normalized == 'main') return null;
    final snapshot = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(normalized)
        .collection('inventory')
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }
}
