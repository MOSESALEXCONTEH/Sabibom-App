import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/theme.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';
import 'package:sabibom/features/billing/domain/billing_resolution.dart';
import 'package:sabibom/features/billing/presentation/billing_screen.dart';

const _plan = SubscriptionPlan(
  id: 'growth-monthly',
  name: 'Growth Pro',
  description: 'Built for busy shops ready to grow.',
  currency: 'SLE',
  price: 125,
  billingInterval: 'monthly',
  features: <String>['Unlimited branches', 'Advanced reports'],
  limits: <String, dynamic>{},
  trialDays: 0,
  tier: 'pro',
  googlePlayProductId: 'growth_monthly',
);

final _freeAccess = ResolvedBusinessEntitlements.resolve(
  subscription: null,
  plans: const <SubscriptionPlan>[],
).withGlobalFreeAccess();

final _normalAccess = ResolvedBusinessEntitlements.resolve(
  subscription: null,
  plans: const <SubscriptionPlan>[],
);

void main() {
  testWidgets('global free access shows policy content and no purchase UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BillingScreenContent(
          globalFreeAccess: true,
          policyMessage:
              'All SabiBom features are currently available free with ads.',
          purchasesEnabled: false,
          isOwner: true,
          plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
            _plan,
          ]),
          access: AsyncData(_freeAccess),
          onRefresh: () async {},
          onRestore: () {},
          onPurchase: (_) {},
          onManage: (_) {},
          onRetryAccess: () {},
          onRetryPlans: () {},
        ),
      ),
    );

    expect(find.text('FULL ACCESS ACTIVE'), findsOneWidget);
    expect(find.text('All Pro tools are yours'), findsOneWidget);
    expect(find.text('Free with ads'), findsOneWidget);
    expect(find.text('No payment needed'), findsOneWidget);
    expect(find.text('Unlimited branches'), findsOneWidget);
    expect(find.text('Unlimited team'), findsOneWidget);
    expect(find.text('Advanced reports'), findsOneWidget);
    expect(find.text('Backup & exports'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pro purchases are paused'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pro purchases are paused'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Refresh access'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Refresh access'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
    expect(find.text('Choose plan'), findsNothing);
    expect(find.text('Growth Pro'), findsNothing);
  });

  testWidgets('normal owner plan uses actual name, store price, and CTA', (
    tester,
  ) async {
    var purchased = false;
    await tester.pumpWidget(
      _app(
        BillingScreenContent(
          globalFreeAccess: false,
          policyMessage: 'Choose the plan that fits your business.',
          purchasesEnabled: true,
          isOwner: true,
          plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
            _plan,
          ]),
          access: AsyncData(_normalAccess),
          storePrices: const <String, String>{'growth_monthly': 'SLE 149.99'},
          onRefresh: () async {},
          onRestore: () {},
          onPurchase: (_) => purchased = true,
          onManage: (_) {},
          onRetryAccess: () {},
          onRetryPlans: () {},
        ),
      ),
    );

    expect(find.text('Grow without limits'), findsOneWidget);
    expect(find.text('Growth Pro'), findsOneWidget);
    expect(find.text('SLE 149.99'), findsOneWidget);
    expect(find.text('Built for busy shops ready to grow.'), findsOneWidget);
    expect(find.text('Secure checkout through Google Play'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('purchase-growth-monthly')),
    );
    expect(purchased, isTrue);
  });

  testWidgets('narrow large-text free-access layout has no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 760),
          textScaler: TextScaler.linear(1.8),
        ),
        child: _app(
          BillingScreenContent(
            globalFreeAccess: true,
            policyMessage:
                'All SabiBom features are currently available free with ads.',
            purchasesEnabled: false,
            isOwner: true,
            plans: const AsyncLoading<List<SubscriptionPlan>>(),
            access: const AsyncLoading<ResolvedBusinessEntitlements>(),
            onRefresh: () async {},
            onPurchase: (_) {},
            onManage: (_) {},
            onRetryAccess: () {},
            onRetryPlans: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Refresh access'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Refresh access'), findsOneWidget);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: SabiBomTheme.light,
    darkTheme: SabiBomTheme.dark,
    home: home,
  );
}
