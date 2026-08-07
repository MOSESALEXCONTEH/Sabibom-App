import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/application/current_branch_providers.dart';
import 'package:sabibom/features/notifications/application/attention_summary_service.dart';
import 'package:sabibom/features/notifications/domain/attention_summary.dart';
import 'package:sabibom/features/notifications/presentation/attention_section.dart';
import 'package:sabibom/features/reports/application/reports_providers.dart';
import 'package:sabibom/features/reports/data/reports_repository.dart';
import 'package:sabibom/features/reports/domain/profit_models.dart';
import 'package:sabibom/features/purchases/application/purchases_providers.dart';
import 'package:sabibom/features/purchases/data/purchases_repository.dart';
import 'package:sabibom/features/purchases/domain/purchase.dart';
import 'package:sabibom/features/products/application/products_providers.dart';
import 'package:sabibom/features/products/data/products_repository.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:sabibom/features/sales/application/sales_providers.dart';
import 'package:sabibom/features/sales/data/sales_repository.dart';
import 'package:sabibom/features/sales/domain/sale.dart';

final _testBranchProvider = NotifierProvider<_TestBranchController, String?>(
  _TestBranchController.new,
);

class _TestBranchController extends Notifier<String?> {
  @override
  String? build() => 'main';

  void select(String? branchId) => state = branchId;
}

class _RecordingAttentionService implements AttentionSummaryService {
  final loadedBranches = <String?>[];

  @override
  Future<AttentionSummary> build({
    required String businessId,
    required String businessName,
    String? branchId,
  }) async {
    loadedBranches.add(branchId);
    return AttentionSummary(
      businessId: businessId,
      businessName: businessName,
      generatedAt: DateTime(2026, 7, 29),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSalesRepository implements SalesRepository {
  final watchedBranches = <String?>[];

  @override
  Stream<List<SaleHistoryItem>> watchRecentSales(
    String businessId, {
    String? branchId,
    int limit = 25,
  }) {
    watchedBranches.add(branchId);
    return Stream.value(const <SaleHistoryItem>[]);
  }

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId, {
    String? branchId,
  }) async => null;

  @override
  Future<Sale?> getSaleDocument(
    String businessId,
    String saleId, {
    String? branchId,
  }) async => null;

  @override
  Future<void> voidSale(
    String businessId,
    String saleId, {
    required String branchId,
    required String reason,
    String? voidedByUid,
    String? voidedByName,
  }) async {}
}

class _RecordingReportsRepository extends ReportsRepository {
  _RecordingReportsRepository() : super(firestore: FakeFirebaseFirestore());

  final loadedBranches = <String?>[];

  @override
  Future<ReportPeriodData> loadProfitLoss(
    String businessId, {
    required DateTime start,
    required DateTime end,
    String? branchId,
  }) async {
    loadedBranches.add(branchId);
    return ReportPeriodData(
      summary: ProfitPeriodSummary.unavailable('test'),
      sales: const [],
      expenses: const [],
      suppliers: const [],
    );
  }
}

class _RecordingPurchasesRepository implements PurchasesRepository {
  final watchedBranches = <String?>[];

  @override
  Stream<List<Purchase>> watchPurchases(String businessId, {String? branchId}) {
    watchedBranches.add(branchId);
    return Stream.value(const <Purchase>[]);
  }

  @override
  Future<Purchase> completePurchase(CompletePurchaseRequest request) =>
      throw UnimplementedError();

  @override
  Future<void> createPurchaseReturn(
    CreatePurchaseReturnRequest request, {
    String? branchId,
  }) async {}

  @override
  Future<Purchase?> getPurchase(
    String businessId,
    String purchaseId, {
    String? branchId,
  }) async => null;

  @override
  Future<void> voidPurchase(
    String businessId,
    String purchaseId, {
    required String reason,
    String? branchId,
  }) async {}
}

class _BranchStockProductsRepository implements ProductsRepository {
  @override
  Stream<List<Product>> watchProducts(String businessId, {String? branchId}) {
    return Stream.value([
      Product(
        id: 'product-1',
        businessId: businessId,
        name: 'Mango',
        sellingPriceMinor: 100,
        costPriceMinor: 50,
        quantity: branchId == 'east' ? 3 : 20,
        lowStockThreshold: 0,
        trackStock: true,
        unit: 'Piece',
        status: ProductStatus.active,
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Main to East rebuilds sales, purchases and reports', () async {
    final sales = _RecordingSalesRepository();
    final purchases = _RecordingPurchasesRepository();
    final reports = _RecordingReportsRepository();
    final container = ProviderContainer(
      overrides: [
        currentBranchReadScopeProvider.overrideWith(
          (ref) => ref.watch(_testBranchProvider),
        ),
        salesRepositoryProvider.overrideWithValue(sales),
        purchasesRepositoryProvider.overrideWithValue(purchases),
        reportsRepositoryProvider.overrideWithValue(reports),
      ],
    );
    addTearDown(container.dispose);

    final request = ProfitReportRequest(
      businessId: 'business-1',
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
    );
    final salesSubscription = container.listen(
      salesHistoryProvider('business-1'),
      (_, _) {},
    );
    final reportsSubscription = container.listen(
      profitReportProvider(request),
      (_, _) {},
    );
    final purchasesSubscription = container.listen(
      purchasesProvider('business-1'),
      (_, _) {},
    );
    addTearDown(salesSubscription.close);
    addTearDown(reportsSubscription.close);
    addTearDown(purchasesSubscription.close);

    await container.read(salesHistoryProvider('business-1').future);
    await container.read(purchasesProvider('business-1').future);
    await container.read(profitReportProvider(request).future);
    container.read(_testBranchProvider.notifier).select('east');
    for (var attempt = 0; attempt < 50; attempt++) {
      if (sales.watchedBranches.contains('east') &&
          purchases.watchedBranches.contains('east') &&
          reports.loadedBranches.contains('east')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(sales.watchedBranches, containsAllInOrder(['main', 'east']));
    expect(purchases.watchedBranches, containsAllInOrder(['main', 'east']));
    expect(reports.loadedBranches, containsAllInOrder(['main', 'east']));
  });

  test('Main to East rebuilds needs-attention data', () async {
    final attention = _RecordingAttentionService();
    final container = ProviderContainer(
      overrides: [
        currentBranchReadScopeProvider.overrideWith(
          (ref) => ref.watch(_testBranchProvider),
        ),
        attentionSummaryServiceProvider.overrideWithValue(attention),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      attentionSummaryProvider('business-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    await container.read(attentionSummaryProvider('business-1').future);
    container.read(_testBranchProvider.notifier).select('east');
    await container.read(attentionSummaryProvider('business-1').future);

    expect(attention.loadedBranches, containsAllInOrder(['main', 'east']));
  });

  test(
    'Sales catalog replaces Main stock with selected branch stock',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentBranchReadScopeProvider.overrideWith(
            (ref) => ref.watch(_testBranchProvider),
          ),
          productsRepositoryProvider.overrideWithValue(
            _BranchStockProductsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        saleProductsProvider('business-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);

      final mainProducts = await container.read(
        saleProductsProvider('business-1').future,
      );
      expect(mainProducts.single.quantity, 20);

      container.read(_testBranchProvider.notifier).select('east');
      final eastProducts = await container.read(
        saleProductsProvider('business-1').future,
      );
      expect(eastProducts.single.quantity, 3);
    },
  );
}
