import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/user_profile_provider.dart';
import '../domain/billing_models.dart';
import '../domain/billing_resolution.dart';

final currentBusinessSubscriptionProvider =
    StreamProvider<BusinessSubscription?>((ref) {
      final businessId = ref
          .watch(currentUserProfileProvider)
          .asData
          ?.value
          ?.activeBusinessId
          ?.trim();
      if (businessId == null || businessId.isEmpty) {
        return Stream<BusinessSubscription?>.value(null);
      }
      return FirebaseFirestore.instance
          .collection('business_subscriptions')
          .doc(businessId)
          .snapshots()
          .map(
            (snapshot) => snapshot.exists && snapshot.data() != null
                ? BusinessSubscription.fromMap(businessId, snapshot.data()!)
                : null,
          );
    });

final activeSubscriptionPlansProvider = StreamProvider<List<SubscriptionPlan>>(
  (ref) => FirebaseFirestore.instance
      .collection('subscription_plans')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => SubscriptionPlan.fromMap(doc.id, doc.data()))
            .toList(growable: false),
      ),
);

final currentBusinessEntitlementsProvider =
    Provider<AsyncValue<ResolvedBusinessEntitlements>>((ref) {
      final subscription = ref.watch(currentBusinessSubscriptionProvider);
      return subscription.when(
        loading: () => const AsyncLoading(),
        error: AsyncError.new,
        data: (value) {
          if (value == null || !value.hasAccessAt(DateTime.now())) {
            return AsyncData(
              ResolvedBusinessEntitlements.resolve(
                subscription: value,
                plans: const <SubscriptionPlan>[],
              ),
            );
          }

          return ref
              .watch(activeSubscriptionPlansProvider)
              .when(
                loading: () => AsyncData(
                  ResolvedBusinessEntitlements.resolve(
                    subscription: value,
                    plans: const <SubscriptionPlan>[],
                  ),
                ),
                error: (_, _) => AsyncData(
                  ResolvedBusinessEntitlements.resolve(
                    subscription: value,
                    plans: const <SubscriptionPlan>[],
                  ),
                ),
                data: (plans) => AsyncData(
                  ResolvedBusinessEntitlements.resolve(
                    subscription: value,
                    plans: plans,
                  ),
                ),
              );
        },
      );
    });
