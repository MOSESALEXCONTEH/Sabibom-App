import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../maintenance/data/runtime_configuration_repository.dart';
import '../../maintenance/domain/runtime_configuration.dart';
import '../application/billing_providers.dart';
import '../data/play_billing_service.dart';
import '../domain/billing_entitlements.dart';
import '../domain/billing_models.dart';
import '../domain/billing_resolution.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  String? _busyProductId;
  Set<String> _queriedProductIds = const <String>{};
  Map<String, ProductDetails> _storeProducts = const <String, ProductDetails>{};

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = ref
        .read(playBillingServiceProvider)
        .purchaseUpdates
        .listen(_handlePurchaseUpdates, onError: _showPurchaseError);
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(currentBusinessEntitlementsProvider);
    final plans = ref.watch(activeSubscriptionPlansProvider);
    final billingPolicy =
        ref.watch(runtimeConfigurationProvider).asData?.value.billing ??
        const RuntimeBillingAccessPolicy();
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = switch (activeBusiness) {
      ActiveBusinessData(:final business) => business.ownerId == currentUid,
      _ => false,
    };

    if (plans.hasValue) {
      _ensureStoreProducts(plans.requireValue);
    }

    return BillingScreenContent(
      purchasesEnabled: billingPolicy.purchasesEnabled,
      isOwner: isOwner,
      plans: plans,
      access: access,
      storePrices: <String, String>{
        for (final entry in _storeProducts.entries)
          entry.key: entry.value.price,
      },
      busyProductId: _busyProductId,
      onRefresh: _refreshAll,
      onRestore: isOwner ? _restorePurchases : null,
      onPurchase: _purchase,
      onManage: _manageSubscription,
      onRetryAccess: () {
        ref.invalidate(currentBusinessSubscriptionProvider);
      },
      onRetryPlans: () {
        ref.invalidate(activeSubscriptionPlansProvider);
      },
    );
  }

  Future<void> _refreshAll() async {
    ref.invalidate(runtimeConfigurationProvider);
    ref.invalidate(currentBusinessSubscriptionProvider);
    ref.invalidate(activeSubscriptionPlansProvider);
    await ref.read(runtimeConfigurationProvider.future);
  }

  Future<void> _purchase(SubscriptionPlan plan) async {
    final productId = plan.googlePlayProductId.trim();
    if (productId.isEmpty) {
      _showPurchaseError(
        StateError('This plan is not connected to Google Play yet.'),
      );
      return;
    }
    setState(() => _busyProductId = productId);
    try {
      final billing = ref.read(playBillingServiceProvider);
      if (!await billing.isAvailable()) {
        throw StateError('Google Play Billing is unavailable on this device.');
      }
      var product = _storeProducts[productId];
      if (product == null) {
        final response = await billing.queryProducts(<String>{productId});
        if (response.error != null) throw StateError(response.error!.message);
        if (response.productDetails.isEmpty) {
          throw StateError(
            'This subscription is not available in Google Play.',
          );
        }
        product = response.productDetails.single;
      }
      await billing.purchase(product);
    } catch (error) {
      _showPurchaseError(error);
    } finally {
      if (mounted) setState(() => _busyProductId = null);
    }
  }

  void _ensureStoreProducts(List<SubscriptionPlan> plans) {
    final ids = plans
        .map((plan) => plan.googlePlayProductId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty || setEquals(ids, _queriedProductIds)) return;
    _queriedProductIds = ids;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final billing = ref.read(playBillingServiceProvider);
        if (!await billing.isAvailable()) return;
        final response = await billing.queryProducts(ids);
        if (!mounted || response.error != null) return;
        setState(() {
          _storeProducts = <String, ProductDetails>{
            for (final product in response.productDetails) product.id: product,
          };
        });
      } catch (_) {
        // Keep the admin catalog price until Google Play is reachable.
      }
    });
  }

  Future<void> _restorePurchases() async {
    setState(() => _busyProductId = 'restore');
    try {
      await ref.read(playBillingServiceProvider).restore();
      _showMessage('Checking previous Google Play purchases...');
    } catch (error) {
      _showPurchaseError(error);
    } finally {
      if (mounted) setState(() => _busyProductId = null);
    }
  }

  Future<void> _manageSubscription(String productId) async {
    final uri = Uri.https(
      'play.google.com',
      '/store/account/subscriptions',
      <String, String>{'sku': productId, 'package': 'com.sabibom.app'},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showPurchaseError(
        StateError('Could not open Google Play subscription settings.'),
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        _showMessage('Google Play is processing the subscription.');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _showPurchaseError(
          StateError(purchase.error?.message ?? 'The purchase failed.'),
        );
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      final active = ref.read(activeBusinessProvider).asData?.value;
      final businessId = switch (active) {
        ActiveBusinessData(:final business) => business.businessId,
        _ => null,
      };
      if (businessId == null) {
        _showPurchaseError(StateError('Select a business and try again.'));
        continue;
      }

      try {
        await ref
            .read(billingVerificationServiceProvider)
            .verifyGooglePlayPurchase(
              businessId: businessId,
              purchase: purchase,
            );
        if (purchase.pendingCompletePurchase) {
          await ref.read(playBillingServiceProvider).complete(purchase);
        }
        ref.invalidate(currentBusinessSubscriptionProvider);
        _showMessage('Subscription verified. Pro features are now available.');
      } catch (error) {
        _showPurchaseError(error);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPurchaseError(Object error) {
    if (!mounted) return;
    final message = error is StateError
        ? error.message
        : 'Could not complete the subscription. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Testable presentation surface for Plans & Billing. It intentionally has no
/// Firebase dependencies; [BillingScreen] owns all purchase orchestration.
@visibleForTesting
class BillingScreenContent extends StatefulWidget {
  const BillingScreenContent({
    required this.purchasesEnabled,
    required this.isOwner,
    required this.plans,
    required this.access,
    required this.onRefresh,
    required this.onPurchase,
    required this.onManage,
    required this.onRetryAccess,
    required this.onRetryPlans,
    this.storePrices = const <String, String>{},
    this.busyProductId,
    this.onRestore,
    super.key,
  });

  final bool purchasesEnabled;
  final bool isOwner;
  final AsyncValue<List<SubscriptionPlan>> plans;
  final AsyncValue<ResolvedBusinessEntitlements> access;
  final Map<String, String> storePrices;
  final String? busyProductId;
  final AsyncCallback onRefresh;
  final VoidCallback? onRestore;
  final ValueChanged<SubscriptionPlan> onPurchase;
  final ValueChanged<String> onManage;
  final VoidCallback onRetryAccess;
  final VoidCallback onRetryPlans;

  @override
  State<BillingScreenContent> createState() => _BillingScreenContentState();
}

class _BillingScreenContentState extends State<BillingScreenContent> {
  final PageController _benefitController = PageController();
  String? _selectedPlanId;
  int _benefitPage = 0;

  @override
  void dispose() {
    _benefitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 380
        ? AppSpacing.md
        : AppSpacing.lg;
    final showRestore =
        widget.purchasesEnabled && widget.isOwner && widget.onRestore != null;
    final selectedPlan = widget.plans.maybeWhen(
      data: _selectedPlan,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('SabiBom Pro'),
        actions: <Widget>[
          if (showRestore)
            TextButton(
              onPressed: widget.busyProductId == null ? widget.onRestore : null,
              child: const Text('Restore'),
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppSpacing.sm,
            horizontalPadding,
            selectedPlan == null ? 40 : 150,
          ),
          children: <Widget>[
            _ProHero(
              controller: _benefitController,
              currentPage: _benefitPage,
              onPageChanged: (page) => setState(() => _benefitPage = page),
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildPlans(context),
            const SizedBox(height: AppSpacing.lg),
            const _FeatureComparison(),
            const SizedBox(height: AppSpacing.lg),
            _buildAccess(context),
          ],
        ),
      ),
      bottomNavigationBar: selectedPlan == null
          ? null
          : _PurchaseFooter(
              plan: selectedPlan,
              canPurchase: widget.isOwner && widget.purchasesEnabled,
              purchasesEnabled: widget.purchasesEnabled,
              busy: widget.busyProductId == selectedPlan.googlePlayProductId,
              onContinue: () => widget.onPurchase(selectedPlan),
            ),
    );
  }

  List<SubscriptionPlan> _recurringProPlans(List<SubscriptionPlan> plans) {
    final recurring = plans
        .where((plan) {
          final interval = _normalizedInterval(plan.billingInterval);
          return plan.tier.trim().toLowerCase() == 'pro' &&
              (interval == 'monthly' || interval == 'yearly');
        })
        .toList(growable: false);
    recurring.sort((a, b) {
      final aRank = _normalizedInterval(a.billingInterval) == 'yearly' ? 0 : 1;
      final bRank = _normalizedInterval(b.billingInterval) == 'yearly' ? 0 : 1;
      final byInterval = aRank.compareTo(bRank);
      return byInterval != 0 ? byInterval : a.price.compareTo(b.price);
    });
    return recurring;
  }

  SubscriptionPlan? _selectedPlan(List<SubscriptionPlan> plans) {
    final recurring = _recurringProPlans(plans);
    if (recurring.isEmpty) return null;
    for (final plan in recurring) {
      if (plan.id == _selectedPlanId) return plan;
    }
    return recurring.first;
  }

  Widget _buildPlans(BuildContext context) {
    return widget.plans.when(
      loading: () => const _BillingLoading(label: 'Loading available plans'),
      error: (error, _) => AppErrorState(
        title: 'Plans are unavailable',
        message: '$error',
        onRetry: widget.onRetryPlans,
      ),
      data: (allPlans) {
        final plans = _recurringProPlans(allPlans);
        if (plans.isEmpty) {
          return const AppEmptyState(
            title: 'Pro subscriptions are coming soon',
            description:
                'Monthly and yearly plans will appear here when available.',
            icon: Icons.workspace_premium_outlined,
          );
        }
        final selected = _selectedPlan(plans)!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose your billing plan',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Both plans unlock the same Pro features. Choose how often you pay.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.mutedTextColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RecurringPlanOption(
                  plan: plan,
                  storePrice: widget.storePrices[plan.googlePlayProductId],
                  selected: plan.id == selected.id,
                  onSelected: () => setState(() => _selectedPlanId = plan.id),
                ),
              ),
            ),
            if (!widget.isOwner) ...<Widget>[
              const _OwnerNotice(purchasesEnabled: true),
            ] else if (!widget.purchasesEnabled) ...<Widget>[
              const _OwnerNotice(purchasesEnabled: false),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAccess(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Current access',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.md),
        widget.access.when(
          loading: () =>
              const _BillingLoading(label: 'Checking current access'),
          error: (error, _) => AppErrorState(
            title: 'Could not load billing',
            message: '$error',
            onRetry: widget.onRetryAccess,
          ),
          data: (value) => BillingAccessSummary(
            access: value,
            onManage:
                widget.isOwner &&
                    widget.purchasesEnabled &&
                    (value.plan?.googlePlayProductId.isNotEmpty ?? false)
                ? () => widget.onManage(value.plan!.googlePlayProductId)
                : null,
          ),
        ),
      ],
    );
  }
}

class _ProHero extends StatelessWidget {
  const _ProHero({
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
  });

  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  static const _benefits = <({IconData icon, String title, String message})>[
    (
      icon: Icons.trending_up_rounded,
      title: 'Grow without limits',
      message: 'Unlimited branches, staff and Sabi requests for your business.',
    ),
    (
      icon: Icons.insights_rounded,
      title: 'See the full picture',
      message: 'Advanced reports, exports and complete business history.',
    ),
    (
      icon: Icons.groups_2_rounded,
      title: 'Run a stronger team',
      message:
          'Approvals, backups and team tools built for growing businesses.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDarkTheme
              ? const <Color>[Color(0xFF171B34), Color(0xFF272052)]
              : const <Color>[Color(0xFFF0F4FF), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: context.brandTintBorder),
        borderRadius: BorderRadius.circular(AppRadii.feature),
      ),
      child: Column(
        children: <Widget>[
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Upgrade to '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFFFB547), Color(0xFFFF7A45)],
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.input),
                    ),
                    child: Text(
                      'PRO',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: ' for unlimited access'),
              ],
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              height: 1.12,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: (150 + ((scale - 1).clamp(0, 1) * 145)).toDouble(),
            child: PageView.builder(
              controller: controller,
              itemCount: _benefits.length,
              onPageChanged: onPageChanged,
              itemBuilder: (context, index) {
                final benefit = _benefits[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: context.elevationShadowColor,
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          benefit.icon,
                          color: scheme.primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        benefit.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          benefit.message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.mutedTextColor,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(_benefits.length, (index) {
              final selected = currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 20 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : context.borderColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RecurringPlanOption extends StatelessWidget {
  const _RecurringPlanOption({
    required this.plan,
    required this.storePrice,
    required this.selected,
    required this.onSelected,
  });

  final SubscriptionPlan plan;
  final String? storePrice;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final interval = _normalizedInterval(plan.billingInterval);
    final yearly = interval == 'yearly';
    final price =
        storePrice ??
        formatCurrency(plan.price, code: plan.currency, symbol: plan.currency);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${yearly ? 'Yearly' : 'Monthly'} Pro plan, $price',
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: selected ? context.brandTint : context.surfaceColor,
            borderRadius: BorderRadius.circular(AppRadii.feature),
            child: InkWell(
              key: ValueKey<String>('plan-option-${plan.id}'),
              borderRadius: BorderRadius.circular(AppRadii.feature),
              onTap: onSelected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? scheme.primary : context.borderColor,
                    width: selected ? 3 : 1.2,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.feature),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? scheme.primary
                              : context.borderColor,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 17,
                            )
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            yearly ? '12 Months' : '1 Month',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            yearly
                                ? 'Billed once every year'
                                : 'Billed monthly',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.mutedTextColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            price,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: selected ? scheme.primary : null,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(
                            yearly ? '/ year' : '/ month',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.mutedTextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (yearly)
            Positioned(
              right: 18,
              top: -11,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFFF6B57), Color(0xFFFF8A45)],
                  ),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFFF6B57).withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'BEST OFFER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureComparison extends StatelessWidget {
  const _FeatureComparison();

  static const _rows = <({String label, String free, String pro})>[
    (label: 'Branches', free: '1', pro: 'Unlimited'),
    (label: 'Team members', free: '2', pro: 'Unlimited'),
    (label: 'Report history', free: '30 days', pro: 'Unlimited'),
    (label: 'Sabi requests', free: '10/day', pro: 'Unlimited'),
    (label: 'Advanced reports', free: '—', pro: 'Included'),
    (label: 'Backups & approvals', free: '—', pro: 'Included'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Enjoy unlimited Pro access',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(AppRadii.feature),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              _ComparisonRow(
                label: 'Features',
                free: 'Free',
                pro: 'PRO',
                header: true,
              ),
              ..._rows.map(
                (row) => _ComparisonRow(
                  label: row.label,
                  free: row.free,
                  pro: row.pro,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.free,
    required this.pro,
    this.header = false,
  });

  final String label;
  final String free;
  final String pro;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = header
        ? Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: header ? context.brandTint : null,
        border: header
            ? null
            : Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(flex: 5, child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              free,
              textAlign: TextAlign.center,
              style: style?.copyWith(
                color: header ? context.mutedTextColor : null,
                fontWeight: header ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: header ? 0.14 : 0.09),
                borderRadius: BorderRadius.circular(AppRadii.input),
              ),
              child: Text(
                pro,
                textAlign: TextAlign.center,
                style: style?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseFooter extends StatelessWidget {
  const _PurchaseFooter({
    required this.plan,
    required this.canPurchase,
    required this.purchasesEnabled,
    required this.busy,
    required this.onContinue,
  });

  final SubscriptionPlan plan;
  final bool canPurchase;
  final bool purchasesEnabled;
  final bool busy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final productAvailable = plan.googlePlayProductId.trim().isNotEmpty;
    final enabled = canPurchase && productAvailable && !busy;
    final label = busy
        ? 'Opening Google Play...'
        : !purchasesEnabled
        ? 'Purchases unavailable'
        : !canPurchase
        ? 'Owner approval required'
        : !productAvailable
        ? 'Coming soon'
        : 'Continue';

    return Material(
      elevation: 16,
      color: context.surfaceColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: enabled
                      ? const LinearGradient(
                          colors: <Color>[AppColors.primary, Color(0xFF635BFF)],
                        )
                      : null,
                  color: enabled ? null : context.borderColor,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: FilledButton(
                  key: ValueKey<String>('purchase-${plan.id}'),
                  onPressed: enabled ? onContinue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (busy) ...<Widget>[
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (enabled) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: <Widget>[
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  Text(
                    'Secure Google Play billing • Cancel anytime',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.mutedTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: <Widget>[
                  TextButton(
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse('https://www.sabibom.com/privacy'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    child: const Text('Privacy Policy'),
                  ),
                  Text('•', style: TextStyle(color: context.mutedTextColor)),
                  TextButton(
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse('https://www.sabibom.com/terms'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    child: const Text('Terms of Use'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerNotice extends StatelessWidget {
  const _OwnerNotice({required this.purchasesEnabled});

  final bool purchasesEnabled;

  @override
  Widget build(BuildContext context) {
    final message = purchasesEnabled
        ? 'Only the business owner can purchase or manage plans.'
        : 'Plan purchases are currently unavailable.';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.brandTint,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

@visibleForTesting
class BillingAccessSummary extends StatelessWidget {
  const BillingAccessSummary({required this.access, this.onManage, super.key});

  final ResolvedBusinessEntitlements access;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final subscription = access.subscription;
    final statusColor = access.wasDowngraded
        ? AppColors.warning
        : AppColors.secondary;
    final end = subscription?.accessEnd;
    final tierName = switch (access.tier) {
      BillingTier.free => 'Free plan',
      BillingTier.pro => 'Pro plan',
      BillingTier.complimentary => 'Complimentary plan',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  access.wasDowngraded
                      ? Icons.info_outline
                      : Icons.verified_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tierName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subscription != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Status: ${subscription.status.replaceAll('_', ' ')}',
                        style: TextStyle(color: context.mutedTextColor),
                      ),
                      if (end != null)
                        Text(
                          'Access until ${DateFormat.yMMMd().add_jm().format(end)}',
                          style: TextStyle(color: context.mutedTextColor),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (access.wasDowngraded) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Your business data remains available. Premium tools are limited '
              'until the subscription is renewed.',
            ),
          ],
          if (onManage != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Manage in Google Play'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingLoading extends StatelessWidget {
  const _BillingLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

String _normalizedInterval(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ? 'billing period' : normalized;
}
