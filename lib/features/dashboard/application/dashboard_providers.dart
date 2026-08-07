import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/date_range_utils.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../branches/domain/business_branch.dart';
import '../../business_setup/domain/business.dart';
import '../../products/application/products_providers.dart';
import '../data/dashboard_repository.dart';
import '../data/firestore_dashboard_repository.dart';
import '../domain/dashboard_models.dart';

sealed class ActiveBusinessState {
  const ActiveBusinessState();
}

class ActiveBusinessLoading extends ActiveBusinessState {
  const ActiveBusinessLoading();
}

class ActiveBusinessNone extends ActiveBusinessState {
  const ActiveBusinessNone();
}

class ActiveBusinessData extends ActiveBusinessState {
  const ActiveBusinessData(this.business);

  final Business business;
}

class ActiveBusinessFailure extends ActiveBusinessState {
  const ActiveBusinessFailure(this.message);

  final String message;
}

final activeBusinessProvider = StreamProvider<ActiveBusinessState>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);

  // Use a Completer to manage the stream across async gaps.
  final controller = StreamController<ActiveBusinessState>();

  profileAsync.when(
    loading: () => controller.add(const ActiveBusinessLoading()),
    error: (error, stackTrace) {
      _log('profile', error, stackTrace, null);
      controller.add(
        const ActiveBusinessFailure('Could not load your user profile.'),
      );
      controller.close();
    },
    data: (user) {
      final businessId = user?.activeBusinessId?.trim();

      if (!hasUsableBusinessId(businessId)) {
        controller.add(const ActiveBusinessNone());
        controller.close();
        return;
      }

      final subscription = FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .snapshots()
          .listen(
            (snapshot) {
              if (!snapshot.exists || snapshot.data() == null) {
                controller.add(
                  const ActiveBusinessFailure(
                    'This business profile could not be found.',
                  ),
                );
              } else {
                controller.add(
                  ActiveBusinessData(Business.fromFirestore(snapshot.data()!)),
                );
              }
            },
            onError: (error, stackTrace) {
              _log('business', error, stackTrace, businessId);
              controller.add(
                ActiveBusinessFailure(_friendlyFirestoreError(error)),
              );
            },
          );

      // When the provider is disposed, cancel the subscription.
      ref.onDispose(() {
        subscription.cancel();
        controller.close();
      });
    },
  );

  return controller.stream;
});

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FirestoreDashboardRepository(),
);

final dashboardPeriodProvider =
    NotifierProvider<DashboardPeriodController, DashboardPeriod>(
      DashboardPeriodController.new,
    );

class DashboardPeriodController extends Notifier<DashboardPeriod> {
  @override
  DashboardPeriod build() => DashboardPeriod.today;

  void select(DashboardPeriod period) => state = period;
}

class DashboardRequest {
  const DashboardRequest({
    required this.businessId,
    required this.period,
    required this.currencyCode,
    required this.currencySymbol,
  });

  final String businessId;
  final DashboardPeriod period;
  final String currencyCode;
  final String currencySymbol;

  @override
  bool operator ==(Object other) =>
      other is DashboardRequest &&
      other.businessId == businessId &&
      other.period == period &&
      other.currencyCode == currencyCode &&
      other.currencySymbol == currencySymbol;

  @override
  int get hashCode =>
      Object.hash(businessId, period, currencyCode, currencySymbol);
}

final dashboardSummaryProvider =
    FutureProvider.family<DashboardSummary, DashboardRequest>((ref, request) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .read(dashboardRepositoryProvider)
          .getSummary(
            businessId: request.businessId,
            period: request.period,
            currencyCode: request.currencyCode,
            currencySymbol: request.currencySymbol,
            branchId: branchId,
          );
    });

final recentActivityProvider =
    StreamProvider.family<List<DashboardActivity>, String>((ref, businessId) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .read(dashboardRepositoryProvider)
          .watchRecentActivity(businessId: businessId, branchId: branchId);
    });

final lowStockProvider =
    FutureProvider.family<List<ProductStockPreview>, String>((
      ref,
      businessId,
    ) async {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      final products = await ref.watch(productsListProvider(businessId).future);
      Set<String>? branchProductIds;
      final normalizedBranchId = normalizeBranchId(branchId);
      if (normalizedBranchId != null && normalizedBranchId != 'main') {
        final inventory = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .collection('branches')
            .doc(normalizedBranchId)
            .collection('inventory')
            .get();
        branchProductIds = inventory.docs.map((doc) => doc.id).toSet();
      }
      return products
          .where(
            (product) =>
                product.isActive &&
                product.trackStock &&
                product.quantity <= product.lowStockThreshold &&
                (branchProductIds == null ||
                    branchProductIds.contains(product.id)),
          )
          .take(5)
          .map(
            (product) => ProductStockPreview(
              id: product.id,
              name: product.name,
              quantity: product.quantity,
              threshold: product.lowStockThreshold,
              unit: product.unit,
            ),
          )
          .toList(growable: false);
    });

final customerBalancesProvider =
    StreamProvider.family<List<CustomerBalancePreview>, String>((
      ref,
      businessId,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .read(dashboardRepositoryProvider)
          .watchCustomerBalances(businessId: businessId, branchId: branchId);
    });

Future<void> refreshDashboard(WidgetRef ref, DashboardRequest request) async {
  ref.invalidate(currentUserProfileProvider);
  ref.invalidate(activeBusinessProvider);
  ref.invalidate(dashboardSummaryProvider(request));
  ref.invalidate(recentActivityProvider(request.businessId));
  ref.invalidate(lowStockProvider(request.businessId));
  ref.invalidate(customerBalancesProvider(request.businessId));
  await ref.read(dashboardSummaryProvider(request).future);
}

String _friendlyFirestoreError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'We could not access this business. Check your account permissions.',
      'unavailable' =>
        'Your latest business information is temporarily unavailable.',
      'unauthenticated' => 'Your session expired. Please sign in again.',
      'not-found' => 'This business profile could not be found.',
      _ => 'Something went wrong while loading your dashboard.',
    };
  }
  return 'Something went wrong while loading your dashboard.';
}

void _log(
  String context,
  Object error,
  StackTrace stackTrace,
  String? businessId,
) {
  if (!kDebugMode) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  debugPrint('Dashboard provider error ($context): $error');
  if (error is FirebaseException) {
    debugPrint(
      'Dashboard Firebase error: code=${error.code}, '
      'message=${error.message}, '
      'uid=$uid, businessId=$businessId',
    );
  }
  debugPrintStack(stackTrace: stackTrace);
}

bool hasUsableBusinessId(String? businessId) =>
    businessId != null && businessId.trim().isNotEmpty;
