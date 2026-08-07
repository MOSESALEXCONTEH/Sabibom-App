import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/network/authenticated_api_client.dart';
import 'package:sabibom/features/notifications/application/stock_alert_service.dart';
import 'package:sabibom/features/notifications/data/notifications_repository.dart';
import 'package:sabibom/features/products/domain/product.dart';

void main() {
  test(
    'low stock dispatch includes only members assigned to the branch',
    () async {
      final firestore = FakeFirebaseFirestore();
      final members = firestore
          .collection('businesses')
          .doc('business')
          .collection('members');
      await members.doc('owner').set({
        'status': 'active',
        'roleId': 'owner',
        'isOwner': true,
      });
      await members.doc('east-staff').set({
        'status': 'active',
        'roleId': 'cashier',
        'assignedBranchIds': ['east'],
      });
      await members.doc('main-staff').set({
        'status': 'active',
        'roleId': 'cashier',
        'assignedBranchIds': ['main'],
      });
      final api = _RecordingApiClient();
      final service = StockAlertService(
        firestore: firestore,
        notifications: NotificationsRepository(firestore: firestore),
        apiClient: api,
      );

      await service.evaluateProduct(
        businessId: 'business',
        businessName: 'Business',
        branchId: 'east',
        product: const Product(
          id: 'rice',
          businessId: 'business',
          name: 'Rice',
          sellingPriceMinor: 1000,
          costPriceMinor: 700,
          quantity: 2,
          lowStockThreshold: 5,
          trackStock: true,
          unit: 'bags',
          status: ProductStatus.active,
        ),
      );

      expect(api.path, '/api/notifications/dispatch-stock-alert');
      expect(api.body?['businessId'], 'business');
      expect(api.body?['branchId'], 'east');
      expect(
        api.body?['eventKeys'],
        containsAll(<String>[
          'low_stock_business_rice_east_owner',
          'low_stock_business_rice_east_east-staff',
        ]),
      );
      expect(
        api.body?['eventKeys'],
        isNot(contains('low_stock_business_rice_east_main-staff')),
      );

      final mainNotifications = await firestore
          .collection('users')
          .doc('main-staff')
          .collection('notifications')
          .get();
      expect(mainNotifications.docs, isEmpty);
    },
  );
}

class _RecordingApiClient implements AuthenticatedApiClient {
  String? path;
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    this.path = path;
    this.body = body;
    return <String, dynamic>{'sent': 1};
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    bool requireAuth = false,
  }) async => <String, dynamic>{};
}
