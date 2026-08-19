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

    if (!billingPolicy.globalFreeAccessEnabled && plans.hasValue) {
      _ensureStoreProducts(plans.requireValue);
    }

    return BillingScreenContent(
      globalFreeAccess: billingPolicy.globalFreeAccessEnabled,
      policyMessage: billingPolicy.message,
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
    required this.globalFreeAccess,
    required this.policyMessage,
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

  final bool globalFreeAccess;
  final String policyMessage;
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
  String? _selectedInterval;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 380
        ? AppSpacing.md
        : AppSpacing.lg;
    final showRestore =
        !widget.globalFreeAccess &&
        widget.purchasesEnabled &&
        widget.isOwner &&
        widget.onRestore != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans & Billing'),
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
            40,
          ),
          children: widget.globalFreeAccess
              ? <Widget>[
                  _FreeAccessHero(message: widget.policyMessage),
                  const SizedBox(height: AppSpacing.lg),
                  const _FreeAccessFeatureGrid(),
                  const SizedBox(height: AppSpacing.lg),
                  const _PurchasesPausedCard(),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh access'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Access is managed securely by SabiBom.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.mutedTextColor,
                    ),
                  ),
                ]
              : <Widget>[
                  const _PlansHero(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildPlans(context),
                  const SizedBox(height: AppSpacing.lg),
                  _buildAccess(context),
                ],
        ),
      ),
    );
  }

  Widget _buildPlans(BuildContext context) {
    return widget.plans.when(
      loading: () => const _BillingLoading(label: 'Loading available plans'),
      error: (error, _) => AppErrorState(
        title: 'Plans are unavailable',
        message: '$error',
        onRetry: widget.onRetryPlans,
      ),
      data: (plans) {
        if (plans.isEmpty) {
          return const AppEmptyState(
            title: 'No active plans',
            description: 'Active plans will appear here.',
            icon: Icons.workspace_premium_outlined,
          );
        }

        final intervals = <String>[];
        for (final plan in plans) {
          final interval = _normalizedInterval(plan.billingInterval);
          if (!intervals.contains(interval)) intervals.add(interval);
        }
        final selected = intervals.contains(_selectedInterval)
            ? _selectedInterval!
            : intervals.first;
        final visiblePlans = plans
            .where(
              (plan) => _normalizedInterval(plan.billingInterval) == selected,
            )
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose your plan',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (intervals.length > 1) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _IntervalSelector(
                intervals: intervals,
                selected: selected,
                onSelected: (value) {
                  setState(() => _selectedInterval = value);
                },
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns =
                    constraints.maxWidth >= 720 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                final cardWidth = useTwoColumns
                    ? (constraints.maxWidth - AppSpacing.md) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: visiblePlans
                      .map(
                        (plan) => SizedBox(
                          width: cardWidth,
                          child: BillingPlanCard(
                            plan: plan,
                            storePrice:
                                widget.storePrices[plan.googlePlayProductId],
                            canPurchase:
                                widget.isOwner && widget.purchasesEnabled,
                            purchasesEnabled: widget.purchasesEnabled,
                            busy:
                                widget.busyProductId ==
                                plan.googlePlayProductId,
                            onPurchase: () => widget.onPurchase(plan),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            if (!widget.isOwner) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _OwnerNotice(purchasesEnabled: widget.purchasesEnabled),
            ] else if (!widget.purchasesEnabled) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
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

class _PlansHero extends StatelessWidget {
  const _PlansHero();

  @override
  Widget build(BuildContext context) {
    return _HeroSurface(
      eyebrow: 'SABIBOM PRO',
      title: 'Grow without limits',
      message:
          'Choose a plan built around your business. Upgrade securely through '
          'Google Play whenever you are ready.',
      trailing: const _BrandMark(),
    );
  }
}

class _FreeAccessHero extends StatelessWidget {
  const _FreeAccessHero({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _HeroSurface(
      eyebrow: 'FULL ACCESS ACTIVE',
      title: 'All Pro tools are yours',
      message: message,
      trailing: const _BrandMark(celebratory: true),
      footer: const Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          _StatusChip(icon: Icons.campaign_outlined, label: 'Free with ads'),
          _StatusChip(
            icon: Icons.credit_card_off_outlined,
            label: 'No payment needed',
          ),
        ],
      ),
    );
  }
}

class _HeroSurface extends StatelessWidget {
  const _HeroSurface({
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.trailing,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String message;
  final Widget trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      header: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDarkTheme
                ? <Color>[AppColors.surfaceDark, const Color(0xFF241D43)]
                : <Color>[Colors.white, const Color(0xFFF1EDFF)],
          ),
          border: Border.all(color: context.brandTintBorder),
          borderRadius: BorderRadius.circular(AppRadii.feature),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: context.elevationShadowColor,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(width: 72, height: 72, child: trailing),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        eyebrow,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.mutedTextColor,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (footer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.celebratory = false});

  final bool celebratory;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: celebratory ? 'SabiBom full access' : 'SabiBom Pro',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.brandTintStrong,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Image.asset(
          'assets/images/SB icon.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.8),
        border: Border.all(color: context.brandTintBorder),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeAccessFeatureGrid extends StatelessWidget {
  const _FreeAccessFeatureGrid();

  static const _features = <(IconData, String, String)>[
    (
      Icons.storefront_outlined,
      'Unlimited branches',
      'Run every location from one workspace.',
    ),
    (
      Icons.groups_outlined,
      'Unlimited team',
      'Bring your whole team into SabiBom.',
    ),
    (
      Icons.insights_outlined,
      'Advanced reports',
      'See deeper trends across your business.',
    ),
    (
      Icons.cloud_download_outlined,
      'Backup & exports',
      'Keep and export your business records.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn =
            constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final width = oneColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: _features
              .map(
                (feature) => SizedBox(
                  width: width,
                  child: _FeatureCard(
                    icon: feature.$1,
                    title: feature.$2,
                    description: feature.$3,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: context.brandTint,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.mutedTextColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchasesPausedCard extends StatelessWidget {
  const _PurchasesPausedCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Pro purchases are paused. You will not be charged while free access '
          'is active. Ads remain enabled.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.brandTint,
          border: Border.all(color: context.brandTintBorder),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Pro purchases are paused',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'You will not be charged while free access is active. '
                    'Ads remain enabled.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalSelector extends StatelessWidget {
  const _IntervalSelector({
    required this.intervals,
    required this.selected,
    required this.onSelected,
  });

  final List<String> intervals;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Billing interval',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: context.brandTint,
          border: Border.all(color: context.brandTintBorder),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: intervals
              .map(
                (interval) => ChoiceChip(
                  label: Text(_displayInterval(interval)),
                  selected: interval == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(interval),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

@visibleForTesting
class BillingPlanCard extends StatelessWidget {
  const BillingPlanCard({
    required this.plan,
    required this.storePrice,
    required this.canPurchase,
    required this.purchasesEnabled,
    required this.busy,
    required this.onPurchase,
    super.key,
  });

  final SubscriptionPlan plan;
  final String? storePrice;
  final bool canPurchase;
  final bool purchasesEnabled;
  final bool busy;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final price =
        storePrice ??
        formatCurrency(plan.price, code: plan.currency, symbol: plan.currency);
    final productAvailable = plan.googlePlayProductId.trim().isNotEmpty;
    return Semantics(
      container: true,
      label:
          '${plan.name}, $price per ${_displayInterval(plan.billingInterval)}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          border: Border.all(color: context.brandTintBorder, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadii.feature),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: context.elevationShadowColor,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              plan.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: <Widget>[
                Text(
                  price,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '/ ${_displayInterval(plan.billingInterval)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.mutedTextColor,
                    ),
                  ),
                ),
              ],
            ),
            if (plan.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                plan.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.mutedTextColor,
                  height: 1.4,
                ),
              ),
            ],
            if (plan.features.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ...plan.features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: context.brandTint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(feature)),
                    ],
                  ),
                ),
              ),
            ],
            if (canPurchase && productAvailable) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[AppColors.primary, Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.input),
                ),
                child: FilledButton.icon(
                  key: ValueKey<String>('purchase-${plan.id}'),
                  onPressed: busy ? null : onPurchase,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.workspace_premium_outlined),
                  label: Text(busy ? 'Opening Google Play...' : 'Choose plan'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: context.mutedTextColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Secure checkout through Google Play',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.mutedTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
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

String _displayInterval(String value) {
  final words = _normalizedInterval(
    value,
  ).replaceAll('_', ' ').replaceAll('-', ' ');
  return words[0].toUpperCase() + words.substring(1);
}
