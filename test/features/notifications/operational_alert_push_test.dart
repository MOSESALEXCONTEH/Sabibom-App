import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/network/authenticated_api_client.dart';
import 'package:sabibom/features/notifications/application/operational_alert_service.dart';

void main() {
  test(
    'operational alert requests contain only trusted source identifiers',
    () async {
      final api = _RecordingApiClient();
      final service = OperationalAlertService(apiClient: api);

      await service.onCustomerCreditCreated(
        businessId: 'business',
        businessName: 'Business',
        branchId: 'main',
        saleId: 'sale-1',
        customerId: 'customer-1',
        customerName: 'Customer',
        balanceMinor: 50000,
      );
      await service.onSupplierCreditCreated(
        businessId: 'business',
        businessName: 'Business',
        branchId: 'main',
        purchaseId: 'purchase-1',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        balanceMinor: 100000,
      );
      await service.onLargeExpense(
        businessId: 'business',
        businessName: 'Business',
        branchId: 'main',
        expenseId: 'expense-1',
        categoryName: 'Transport',
        amountMinor: 200000,
        recordedBy: 'Owner',
      );

      expect(api.calls, hasLength(3));
      for (final call in api.calls) {
        expect(call.path, '/api/notifications/dispatch-operational-alert');
        expect(call.body['businessId'], 'business');
        expect(call.body['branchId'], 'main');
        expect(call.body.keys, <String>[
          'businessId',
          'branchId',
          'category',
          'sourceId',
        ]);
      }
      expect(api.calls[0].body['category'], 'customer_debt');
      expect(api.calls[0].body['sourceId'], 'sale-1');
      expect(api.calls[1].body['category'], 'supplier_credit');
      expect(api.calls[1].body['sourceId'], 'purchase-1');
      expect(api.calls[2].body['category'], 'large_expense');
      expect(api.calls[2].body['sourceId'], 'expense-1');
    },
  );

  test(
    'operational push failure never escapes to the saved transaction',
    () async {
      final service = OperationalAlertService(apiClient: _FailingApiClient());

      await expectLater(
        service.onLargeExpense(
          businessId: 'business',
          businessName: 'Business',
          branchId: 'main',
          expenseId: 'expense-1',
          categoryName: 'Transport',
          amountMinor: 200000,
          recordedBy: 'Owner',
        ),
        completes,
      );
    },
  );
}

class _ApiCall {
  const _ApiCall(this.path, this.body);

  final String path;
  final Map<String, dynamic> body;
}

class _RecordingApiClient implements AuthenticatedApiClient {
  final calls = <_ApiCall>[];

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    calls.add(_ApiCall(path, body));
    return <String, dynamic>{'sent': 1};
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    bool requireAuth = false,
  }) async => <String, dynamic>{};
}

class _FailingApiClient implements AuthenticatedApiClient {
  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 40),
  }) async => throw StateError('offline');

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    bool requireAuth = false,
  }) async => <String, dynamic>{};
}
