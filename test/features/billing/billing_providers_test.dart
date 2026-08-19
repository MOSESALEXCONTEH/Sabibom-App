import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/application/billing_providers.dart';
import 'package:sabibom/features/billing/domain/billing_entitlements.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';
import 'package:sabibom/features/billing/domain/billing_resolution.dart';
import 'package:sabibom/features/billing/presentation/billing_gate.dart';
import 'package:sabibom/features/maintenance/data/runtime_configuration_repository.dart';
import 'package:sabibom/features/maintenance/domain/runtime_configuration.dart';

const _maintenanceOff = RuntimeMaintenanceConfiguration(
  enabled: false,
  effectiveEnabled: false,
  scope: 'all',
  message: '',
);

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
    },
  );

  test('global policy unlocks Free entitlements and retains ads', () {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigurationProvider.overrideWithValue(
          const AsyncData(
            RuntimeConfiguration(
              maintenance: _maintenanceOff,
              billing: RuntimeBillingAccessPolicy(
                schemaVersion: 1,
                globalFreeAccessEnabled: true,
                purchasesEnabled: false,
              ),
            ),
          ),
        ),
        currentBusinessSubscriptionProvider.overrideWithValue(
          const AsyncData(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolved = container.read(currentBusinessEntitlementsProvider);
    expect(
      resolved.requireValue.source,
      EntitlementResolutionSource.globalFreeAccess,
    );
    expect(
      resolved.requireValue.entitlements.isUnlimited(
        BillingEntitlementKeys.branchesMax,
      ),
      isTrue,
    );
    expect(
      resolved.requireValue.entitlements.isEnabled(
        BillingEntitlementKeys.adsEnabled,
      ),
      isTrue,
    );
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
