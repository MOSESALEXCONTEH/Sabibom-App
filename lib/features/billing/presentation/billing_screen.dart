import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../dashboard/application/dashboard_providers.dart';
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
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = switch (activeBusiness) {
      ActiveBusinessData(:final business) => business.ownerId == currentUid,
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans & Billing'),
        actions: <Widget>[
          if (isOwner)
            TextButton(
              onPressed: _busyProductId == null ? _restorePurchases : null,
              child: const Text('Restore'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentBusinessSubscriptionProvider);
          ref.invalidate(activeSubscriptionPlansProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            40,
          ),
          children: <Widget>[
            access.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AppErrorState(
                title: 'Could not load billing',
                message: '$error',
                onRetry: () =>
                    ref.invalidate(currentBusinessSubscriptionProvider),
              ),
              data: (value) => _AccessCard(
                access: value,
                onManage:
                    isOwner &&
                        (value.plan?.googlePlayProductId.isNotEmpty ?? false)
                    ? () => _manageSubscription(value.plan!.googlePlayProductId)
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Available plans',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            plans.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('Plans are unavailable: $error'),
              data: (items) {
                _ensureStoreProducts(items);
                return items.isEmpty
                    ? const AppEmptyState(
                        title: 'No active plans',
                        description: 'Active plans will appear here.',
                      )
                    : Column(
                        children: items
                            .map(
                              (plan) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _PlanCard(
                                  plan: plan,
                                  storePrice:
                                      _storeProducts[plan.googlePlayProductId]
                                          ?.price,
                                  canPurchase: isOwner,
                                  busy:
                                      _busyProductId ==
                                      plan.googlePlayProductId,
                                  onPurchase: () => _purchase(plan),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      );
              },
            ),
          ],
        ),
      ),
    );
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

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.access, this.onManage});
  final ResolvedBusinessEntitlements access;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final subscription = access.subscription;
    final color = access.wasDowngraded ? Colors.orange : Colors.green;
    final end = subscription?.accessEnd;
    final tierName = switch (access.tier) {
      BillingTier.free => 'Free',
      BillingTier.pro => 'Pro',
      BillingTier.complimentary => 'Complimentary',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                access.wasDowngraded
                    ? Icons.info_outline
                    : Icons.verified_outlined,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$tierName plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subscription != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('Status: ${subscription.status.replaceAll('_', ' ')}'),
            if (end != null)
              Text('Access until ${DateFormat.yMMMd().add_jm().format(end)}'),
          ],
          if (access.wasDowngraded) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your business data remains available. Premium tools are limited '
              'until the subscription is renewed.',
            ),
          ],
          if (onManage != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Manage in Google Play'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.storePrice,
    required this.canPurchase,
    required this.busy,
    required this.onPurchase,
  });
  final SubscriptionPlan plan;
  final String? storePrice;
  final bool canPurchase;
  final bool busy;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final price =
        storePrice ??
        formatCurrency(plan.price, code: plan.currency, symbol: plan.currency);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  plan.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('$price / ${plan.billingInterval.replaceAll('_', ' ')}'),
            ],
          ),
          if (plan.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(plan.description),
          ],
          if (plan.features.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ...plan.features.map(
              (feature) => Row(
                children: <Widget>[
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
          ],
          if (canPurchase && plan.googlePlayProductId.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPurchase,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.workspace_premium_outlined),
                label: Text(busy ? 'Opening Google Play...' : 'Choose plan'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
