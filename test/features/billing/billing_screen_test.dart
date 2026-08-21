import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/theme.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';
import 'package:sabibom/features/billing/domain/billing_resolution.dart';
import 'package:sabibom/features/billing/presentation/billing_screen.dart';

const _monthlyPlan = SubscriptionPlan(
  id: 'growth-monthly',
  name: 'Growth Pro Monthly',
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

const _yearlyPlan = SubscriptionPlan(
  id: 'growth-yearly',
  name: 'Growth Pro Yearly',
  description: 'Best value for a full year.',
  currency: 'SLE',
  price: 1200,
  billingInterval: 'yearly',
  features: <String>['Unlimited branches', 'Advanced reports'],
  limits: <String, dynamic>{},
  trialDays: 0,
  tier: 'pro',
  googlePlayProductId: 'growth_yearly',
);

const _oneTimePlan = SubscriptionPlan(
  id: 'growth-lifetime',
  name: 'Lifetime',
  description: 'Retired lifetime offer.',
  currency: 'SLE',
  price: 5000,
  billingInterval: 'one_time',
  features: <String>['Unlimited branches'],
  limits: <String, dynamic>{},
  trialDays: 0,
  tier: 'pro',
  googlePlayProductId: 'growth_lifetime',
);

final _freeAccess = ResolvedBusinessEntitlements.resolve(
  subscription: null,
  plans: const <SubscriptionPlan>[],
);

void main() {
  testWidgets(
    'owner sees yearly and monthly Pro plans with yearly selected by default',
    (tester) async {
      SubscriptionPlan? purchased;
      await tester.pumpWidget(
        _app(
          BillingScreenContent(
            purchasesEnabled: true,
            isOwner: true,
            plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
              _monthlyPlan,
              _oneTimePlan,
              _yearlyPlan,
            ]),
            access: AsyncData(_freeAccess),
            storePrices: const <String, String>{
              'growth_monthly': 'SLE 149.99',
              'growth_yearly': 'SLE 1,499.99',
            },
            onRefresh: () async {},
            onRestore: () {},
            onPurchase: (plan) => purchased = plan,
            onManage: (_) {},
            onRetryAccess: () {},
            onRetryPlans: () {},
          ),
        ),
      );

      expect(find.textContaining('unlimited access'), findsOneWidget);
      expect(find.text('12 Months'), findsOneWidget);
      expect(find.text('1 Month'), findsOneWidget);
      expect(find.text('BEST OFFER'), findsOneWidget);
      expect(find.text('SLE 1,499.99'), findsOneWidget);
      expect(find.text('SLE 149.99'), findsOneWidget);
      expect(find.text('Lifetime'), findsNothing);
      expect(
        find.text('Secure Google Play billing • Cancel anytime'),
        findsOneWidget,
      );
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('purchase-growth-yearly')),
      );
      expect(purchased?.id, 'growth-yearly');

      final monthlyOption = find.byKey(
        const ValueKey<String>('plan-option-growth-monthly'),
      );
      await tester.ensureVisible(monthlyOption);
      await tester.pumpAndSettle();
      await tester.tap(monthlyOption);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('purchase-growth-monthly')),
      );
      expect(purchased?.id, 'growth-monthly');

      await tester.scrollUntilVisible(
        find.text('Enjoy unlimited Pro access'),
        300,
      );
      expect(find.text('Enjoy unlimited Pro access'), findsOneWidget);
    },
  );

  testWidgets('non-owner can compare plans but cannot start a purchase', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BillingScreenContent(
          purchasesEnabled: true,
          isOwner: false,
          plans: const AsyncData<List<SubscriptionPlan>>(<SubscriptionPlan>[
            _monthlyPlan,
            _yearlyPlan,
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

    expect(find.text('12 Months'), findsOneWidget);
    expect(find.text('1 Month'), findsOneWidget);
    expect(
      find.text('Only the business owner can purchase or manage plans.'),
      findsOneWidget,
    );
    expect(find.text('Owner approval required'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('purchase-growth-yearly')),
    );
    expect(button.onPressed, isNull);
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
              _monthlyPlan,
              _yearlyPlan,
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
    expect(find.textContaining('unlimited access'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('BEST OFFER'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('BEST OFFER'), findsOneWidget);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: SabiBomTheme.light,
    darkTheme: SabiBomTheme.dark,
    home: home,
  );
}
