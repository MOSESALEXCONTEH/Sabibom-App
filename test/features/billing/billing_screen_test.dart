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
);

void main() {
  testWidgets(
    'owner sees the ad-free Pro plan and Google Play purchase action',
    (tester) async {
      var purchased = false;
      await tester.pumpWidget(
        _app(
          BillingScreenContent(
            purchasesEnabled: true,
            isOwner: true,
            plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
              _plan,
            ]),
            access: AsyncData(_freeAccess),
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
      expect(find.text('Free with ads'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('purchase-growth-monthly')),
      );
      expect(purchased, isTrue);
    },
  );

  testWidgets('non-owner can view plans but cannot start a purchase', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BillingScreenContent(
          purchasesEnabled: true,
          isOwner: false,
          plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
            _plan,
          ]),
          access: AsyncData(_freeAccess),
          onRefresh: () async {},
          onPurchase: (_) {},
          onManage: (_) {},
          onRetryAccess: () {},
          onRetryPlans: () {},
        ),
      ),
    );

    expect(find.text('Growth Pro'), findsOneWidget);
    expect(
      find.text('Only the business owner can purchase or manage plans.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('purchase-growth-monthly')),
      findsNothing,
    );
  });

  testWidgets('narrow large-text Pro layout has no overflow', (tester) async {
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
            purchasesEnabled: true,
            isOwner: true,
            plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
              _plan,
            ]),
            access: AsyncData(_freeAccess),
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
    expect(find.text('Grow without limits'), findsOneWidget);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: SabiBomTheme.light,
    darkTheme: SabiBomTheme.dark,
    home: home,
  );
}
