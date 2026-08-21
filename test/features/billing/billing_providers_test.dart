import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/application/billing_providers.dart';
import 'package:sabibom/features/billing/domain/billing_entitlements.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';
import 'package:sabibom/features/billing/domain/billing_resolution.dart';
import 'package:sabibom/features/billing/presentation/billing_gate.dart';

void main() {
  test('active paid access remains Pro while plan catalog is loading', () {
    final container = ProviderContainer(
      overrides: [
        currentBusinessSubscriptionProvider.overrideWithValue(
          const AsyncData(
            BusinessSubscription(
              businessId: 'business-1',
              planId: 'pro-monthly',
              status: 'active',
              accessType: 'paid',
            ),
          ),
        ),
        activeSubscriptionPlansProvider.overrideWithValue(
          const AsyncLoading<List<SubscriptionPlan>>(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolved = container.read(currentBusinessEntitlementsProvider);

    expect(resolved.requireValue.tier, BillingTier.pro);
    expect(
      resolved.requireValue.source,
      EntitlementResolutionSource.activePlan,
    );
  });

  test(
    'inactive subscription resolves to Free without loading plan catalog',
    () {
      final container = ProviderContainer(
        overrides: [
          currentBusinessSubscriptionProvider.overrideWithValue(
            const AsyncData(
              BusinessSubscription(
                businessId: 'business-1',
                planId: 'pro-monthly',
                status: 'paused',
                accessType: 'paid',
              ),
            ),
          ),
          activeSubscriptionPlansProvider.overrideWithValue(
            const AsyncLoading<List<SubscriptionPlan>>(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final resolved = container.read(currentBusinessEntitlementsProvider);

      expect(resolved.requireValue.tier, BillingTier.free);
      expect(
        resolved.requireValue.entitlements.isEnabled(
          BillingEntitlementKeys.reportsAdvanced,
        ),
        isFalse,
      );
    },
  );

  testWidgets('entitlement gate shows loading instead of a Pro paywall', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBusinessEntitlementsProvider.overrideWithValue(
            const AsyncLoading(),
          ),
        ],
        child: const MaterialApp(
          home: EntitlementGate(
            entitlementKey: BillingEntitlementKeys.reportsAdvanced,
            featureName: 'Business Health AI Score',
            child: Text('Business health content'),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('is a Pro feature'), findsNothing);
  });

  testWidgets('Free business sees a Pro gate for premium tools', (
    tester,
  ) async {
    final resolved = ResolvedBusinessEntitlements.resolve(
      subscription: null,
      plans: const <SubscriptionPlan>[],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBusinessEntitlementsProvider.overrideWithValue(
            AsyncData(resolved),
          ),
        ],
        child: const MaterialApp(
          home: EntitlementGate(
            entitlementKey: BillingEntitlementKeys.reportsAdvanced,
            featureName: 'Business Health AI Score',
            child: Text('Business health content'),
          ),
        ),
      ),
    );

    expect(find.text('Business health content'), findsNothing);
    expect(
      find.text('Business Health AI Score is a Pro feature'),
      findsOneWidget,
    );
    expect(find.text('View plans'), findsOneWidget);
  });

  testWidgets('Free report history hides records older than 30 days', (
    tester,
  ) async {
    final resolved = ResolvedBusinessEntitlements.resolve(
      subscription: null,
      plans: const <SubscriptionPlan>[],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBusinessEntitlementsProvider.overrideWithValue(
            AsyncData(resolved),
          ),
        ],
        child: MaterialApp(
          home: ReportHistoryGate(
            reportDate: DateTime.now().subtract(const Duration(days: 31)),
            child: const Text('Old report'),
          ),
        ),
      ),
    );

    expect(find.text('Old report'), findsNothing);
    expect(find.textContaining('30 days'), findsOneWidget);
  });
}
