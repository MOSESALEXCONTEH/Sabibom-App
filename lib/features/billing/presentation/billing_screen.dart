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

const _paywallBlue = Color(0xFF3977F5);
const _paywallCanvas = Color(0xFFF5F7FF);

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
      backgroundColor: context.isDarkTheme
          ? AppColors.backgroundDark
          : _paywallCanvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.sm,
              horizontalPadding,
              selectedPlan == null ? 40 : 190,
            ),
            children: <Widget>[
              _PaywallHeader(
                onClose: () => Navigator.of(context).maybePop(),
                onRestore: showRestore && widget.busyProductId == null
                    ? widget.onRestore
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _ProHero(
                controller: _benefitController,
                currentPage: _benefitPage,
                onPageChanged: (page) => setState(() => _benefitPage = page),
              ),
              const SizedBox(height: AppSpacing.xl),
              _buildPlans(context),
              const SizedBox(height: AppSpacing.xl),
              const _FeatureComparison(),
              const SizedBox(height: AppSpacing.xl),
              _buildAccess(context),
            ],
          ),
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

class _PaywallHeader extends StatelessWidget {
  const _PaywallHeader({required this.onClose, required this.onRestore});

  final VoidCallback onClose;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    Widget circularControl({required Widget child}) {
      return Material(
        color: context.surfaceColor,
        elevation: 3,
        shadowColor: context.elevationShadowColor,
        shape: const CircleBorder(),
        child: SizedBox.square(dimension: 48, child: child),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        circularControl(
          child: IconButton(
            key: const ValueKey<String>('close-paywall'),
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        circularControl(
          child: PopupMenuButton<String>(
            key: const ValueKey<String>('paywall-menu'),
            tooltip: 'More options',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'restore') onRestore?.call();
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'restore',
                enabled: onRestore != null,
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.restore_rounded),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Restore purchases',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      icon: Icons.receipt_long_rounded,
      title: 'Professional business documents',
      message:
          'Create polished invoices, receipts and estimates in your brand.',
    ),
    (
      icon: Icons.insights_rounded,
      title: 'See the full picture',
      message: 'Advanced reports, exports and complete business history.',
    ),
    (
      icon: Icons.groups_2_rounded,
      title: 'Grow without limits',
      message: 'Unlimited branches, staff and Sabi requests for your business.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Column(
      children: <Widget>[
        Semantics(
          key: const ValueKey<String>('paywall-title'),
          header: true,
          label: 'Upgrade to Pro for Unlimited Access',
          child: Column(
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'Upgrade to',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                          ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFFFFB844), Color(0xFFFF8A2B)],
                        ),
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: const Color(
                              0xFFFF9E35,
                            ).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          height: 1,
                        ),
                      ),
                    ),
                    Text(
                      'for',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                'Unlimited Access',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  height: 1.12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: (220 + ((scale - 1).clamp(0, 1) * 90)).toDouble(),
          child: PageView.builder(
            controller: controller,
            itemCount: _benefits.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final benefit = _benefits[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: _BenefitArtwork(index: index, icon: benefit.icon),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      benefit.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
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
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? _paywallBlue : context.borderColor,
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BenefitArtwork extends StatelessWidget {
  const _BenefitArtwork({required this.index, required this.icon});

  final int index;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (index == 0) return const _InvoiceArtwork();
    final colors = index == 1
        ? const <Color>[Color(0xFFE8EEFF), Color(0xFFDCE7FF)]
        : const <Color>[Color(0xFFF0E8FF), Color(0xFFE9DEFF)];
    return Center(
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1A3766D5),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: _paywallBlue, size: 72),
          ),
        ),
      ),
    );
  }
}

class _InvoiceArtwork extends StatelessWidget {
  const _InvoiceArtwork();

  @override
  Widget build(BuildContext context) {
    const swatches = <Color>[
      Color(0xFFB94AD7),
      Color(0xFF8657E8),
      Color(0xFF3977F5),
      Color(0xFF24BCD0),
      Color(0xFF50C881),
      Color(0xFFF6D747),
      Color(0xFFFFAF2F),
    ];
    return Center(
      child: SizedBox(
        width: 270,
        height: 170,
        child: Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            Positioned(
              top: 57,
              child: Container(
                width: 220,
                height: 108,
                padding: const EdgeInsets.fromLTRB(18, 29, 18, 12),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: context.elevationShadowColor,
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    Container(height: 9, color: _paywallBlue),
                    const SizedBox(height: 9),
                    ...List<Widget>.generate(
                      3,
                      (_) => Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 17,
                              height: 4,
                              color: context.borderColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                height: 4,
                                color: context.borderColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 28,
                              height: 4,
                              color: context.borderColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 6,
              child: Container(
                width: 258,
                height: 88,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x223766D5),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: swatches
                            .map(
                              (color) => Expanded(
                                child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius:
                                        color == const Color(0xFF3977F5)
                                        ? BorderRadius.circular(7)
                                        : null,
                                    border: color == const Color(0xFF3977F5)
                                        ? Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 24,
                      height: 55,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 4),
                      child: const CircleAvatar(
                        radius: 7,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
    final totalPrice =
        storePrice ??
        formatCurrency(plan.price, code: plan.currency, symbol: plan.currency);
    final weeklyPrice = formatCurrency(
      plan.price / (yearly ? 52 : 4.345),
      code: plan.currency,
      symbol: plan.currency,
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 370 || scale > 1.25;

    final planName = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          yearly ? '12 Months' : '1 Month',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          totalPrice,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.mutedTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final weekly = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          weeklyPrice,
          textAlign: compact ? TextAlign.start : TextAlign.end,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: selected ? _paywallBlue : context.mutedTextColor,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        Text(
          '/ week',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.mutedTextColor),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${yearly ? 'Yearly' : 'Monthly'} Pro plan, $totalPrice',
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              key: ValueKey<String>('plan-option-${plan.id}'),
              borderRadius: BorderRadius.circular(30),
              onTap: onSelected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 27, 22, 24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? _paywallBlue : context.borderColor,
                    width: selected ? 3.5 : 1.25,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: selected
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x183977F5),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          planName,
                          const SizedBox(height: AppSpacing.md),
                          weekly,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(child: planName),
                          const SizedBox(width: AppSpacing.md),
                          weekly,
                        ],
                      ),
              ),
            ),
          ),
          if (yearly)
            Positioned(
              right: 18,
              top: -13,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFFF5F56), Color(0xFFFF7757)],
                  ),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x38FF5F56),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'BEST OFFER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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
    (label: 'Advanced reports', free: 'No', pro: 'Yes'),
    (label: 'Backups & approvals', free: 'No', pro: 'Yes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Enjoy Unlimited PRO Access',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          decoration: BoxDecoration(
            color: context.isDarkTheme
                ? const Color(0xFF20283B)
                : const Color(0xFFF0F3FF),
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              const _ComparisonRow(
                label: 'Features',
                free: 'Free',
                pro: 'PRO',
                header: true,
                first: true,
              ),
              ...List<_ComparisonRow>.generate(_rows.length, (index) {
                final row = _rows[index];
                return _ComparisonRow(
                  label: row.label,
                  free: row.free,
                  pro: row.pro,
                  last: index == _rows.length - 1,
                );
              }),
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
    this.first = false,
    this.last = false,
  });

  final String label;
  final String free;
  final String pro;
  final bool header;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final baseStyle = header
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final negative = !header && free == 'No';
    final positive = !header && pro == 'Yes';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 8, 17),
              child: Text(label, style: baseStyle),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: negative
                  ? const Icon(Icons.close_rounded, color: Color(0xFFFF655A))
                  : Text(
                      free,
                      textAlign: TextAlign.center,
                      style: baseStyle?.copyWith(
                        color: header ? context.mutedTextColor : null,
                      ),
                    ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 17),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.vertical(
                  top: first ? const Radius.circular(22) : Radius.zero,
                  bottom: last ? const Radius.circular(22) : Radius.zero,
                ),
              ),
              alignment: Alignment.center,
              child: positive
                  ? const Icon(Icons.check_rounded, color: Color(0xFF44D7A8))
                  : Text(
                      pro,
                      textAlign: TextAlign.center,
                      style: baseStyle?.copyWith(
                        color: header ? _paywallBlue : null,
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
      elevation: 18,
      shadowColor: context.elevationShadowColor,
      color: context.isDarkTheme ? AppColors.backgroundDark : _paywallCanvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: ValueKey<String>('purchase-${plan.id}'),
                  onPressed: enabled ? onContinue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _paywallBlue,
                    disabledBackgroundColor: context.borderColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: enabled ? 5 : 0,
                    shadowColor: const Color(0x553977F5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (busy) ...<Widget>[
                        const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (enabled) ...<Widget>[
                        const SizedBox(width: AppSpacing.lg),
                        const Icon(Icons.arrow_forward_rounded, size: 28),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.schedule_rounded, size: 20, color: _paywallBlue),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'CANCEL ANYTIME',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _paywallBlue,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
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
                  Text('|', style: TextStyle(color: context.mutedTextColor)),
                  TextButton(
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse('https://www.sabibom.com/terms'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    child: const Text('User Agreement'),
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
