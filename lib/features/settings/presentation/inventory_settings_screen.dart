import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../inventory/domain/inventory_expiry_settings.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';

/// Defaults for stock tracking, low-stock alerts, and expiry reminders.
class InventorySettingsScreen extends ConsumerStatefulWidget {
  const InventorySettingsScreen({super.key});

  @override
  ConsumerState<InventorySettingsScreen> createState() =>
      _InventorySettingsScreenState();
}

class _InventorySettingsScreenState
    extends ConsumerState<InventorySettingsScreen> {
  final _threshold = TextEditingController(text: '5');
  final _reminderDays = TextEditingController(text: '30,14,7,3,1,0');
  var _trackByDefault = true;
  var _allowNegative = false;
  var _costStrategy = 'weighted_average';
  var _expiryEnabled = true;
  var _notifyOwners = true;
  var _notifyManagers = true;
  var _notifyStockKeepers = true;
  var _pushEnabled = true;
  var _inAppEnabled = true;
  var _salePolicy = ExpiredStockSalePolicy.block;
  var _hydrated = false;
  var _expiryHydrated = false;
  var _saving = false;

  @override
  void dispose() {
    _threshold.dispose();
    _reminderDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessId =
        ref.watch(currentUserProfileProvider).asData?.value?.activeBusinessId;
    if (businessId == null || businessId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No business has been set up yet.')),
      );
    }

    final canManageExpiry = ref.watch(
          hasPermissionProvider(AppPermission.manageProductExpiry),
        ) ||
        ref.watch(hasPermissionProvider(AppPermission.editBusinessSettings));
    final expiryAsync = ref.watch(inventoryExpirySettingsProvider(businessId));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null && !_hydrated) {
          _hydrated = true;
          _trackByDefault = data['trackStockByDefault'] as bool? ?? true;
          _allowNegative = data['allowNegativeStock'] as bool? ?? false;
          _costStrategy =
              data['costPriceStrategy'] as String? ?? 'weighted_average';
          _threshold.text =
              ((data['defaultLowStockThreshold'] as num?)?.toDouble() ?? 5)
                  .toString();
        }

        expiryAsync.whenData((settings) {
          if (!_expiryHydrated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _expiryHydrated) return;
              setState(() {
                _expiryHydrated = true;
                _expiryEnabled = settings.enabled;
                _notifyOwners = settings.notifyOwners;
                _notifyManagers = settings.notifyManagers;
                _notifyStockKeepers = settings.notifyStockKeepers;
                _pushEnabled = settings.pushEnabled;
                _inAppEnabled = settings.inAppEnabled;
                _salePolicy = settings.expiredStockSalePolicy;
                _reminderDays.text = settings.defaultReminderDays.join(',');
              });
            });
          }
        });

        return Scaffold(
          appBar: AppBar(title: const Text('Inventory Settings')),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: <Widget>[
              Text(
                'These defaults apply when you add new products. You can still '
                'override them on each product.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Track stock by default'),
                subtitle: const Text(
                  'New products start with quantity tracking turned on.',
                ),
                value: _trackByDefault,
                onChanged: (value) => setState(() => _trackByDefault = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow selling below zero'),
                subtitle: const Text(
                  'Useful for services or items you restock after sale.',
                ),
                value: _allowNegative,
                onChanged: (value) => setState(() => _allowNegative = value),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _costStrategy,
                decoration: const InputDecoration(
                  labelText: 'Cost price update on purchase',
                  helperText:
                      'How product cost changes when you complete a stock purchase.',
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'weighted_average',
                    child: Text('Weighted average (recommended)'),
                  ),
                  DropdownMenuItem(
                    value: 'latest',
                    child: Text('Use latest purchase cost'),
                  ),
                  DropdownMenuItem(
                    value: 'keep',
                    child: Text('Keep current cost'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _costStrategy = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _threshold,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default low-stock threshold',
                  helperText:
                      'Products at or below this quantity appear as low stock.',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Expiry alerts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Stored at businesses/$businessId/settings/inventory_expiry',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable expiry reminders'),
                value: _expiryEnabled,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _expiryEnabled = value)
                    : null,
              ),
              TextFormField(
                controller: _reminderDays,
                enabled: canManageExpiry,
                decoration: const InputDecoration(
                  labelText: 'Reminder days',
                  helperText: 'Comma-separated days before expiry (e.g. 30,14,7,3,1,0).',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ExpiredStockSalePolicy>(
                initialValue: _salePolicy,
                decoration: const InputDecoration(
                  labelText: 'Expired stock sale policy',
                ),
                items: const [
                  DropdownMenuItem(
                    value: ExpiredStockSalePolicy.block,
                    child: Text('Block expired stock from sales'),
                  ),
                  DropdownMenuItem(
                    value: ExpiredStockSalePolicy.warn,
                    child: Text('Warn but allow sale'),
                  ),
                ],
                onChanged: canManageExpiry
                    ? (value) {
                        if (value != null) {
                          setState(() => _salePolicy = value);
                        }
                      }
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify owners'),
                value: _notifyOwners,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _notifyOwners = value)
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify managers'),
                value: _notifyManagers,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _notifyManagers = value)
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify stock keepers'),
                value: _notifyStockKeepers,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _notifyStockKeepers = value)
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('In-app notifications'),
                value: _inAppEnabled,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _inAppEnabled = value)
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Push notifications'),
                value: _pushEnabled,
                onChanged: canManageExpiry
                    ? (value) => setState(() => _pushEnabled = value)
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _save(businessId, canManageExpiry: canManageExpiry),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save inventory settings'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(
    String businessId, {
    required bool canManageExpiry,
  }) async {
    final threshold = double.tryParse(_threshold.text.trim()) ?? 5;
    if (threshold < 0 || !threshold.isFinite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid low-stock threshold.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('businesses').doc(businessId).set(
        <String, Object?>{
          'trackStockByDefault': _trackByDefault,
          'allowNegativeStock': _allowNegative,
          'defaultLowStockThreshold': threshold,
          'costPriceStrategy': _costStrategy,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (canManageExpiry) {
        final days = _reminderDays.text
            .split(',')
            .map((part) => int.tryParse(part.trim()))
            .whereType<int>();
        final uid = ref.read(currentUserProfileProvider).asData?.value?.uid;
        await saveInventoryExpirySettings(
          businessId: businessId,
          settings: InventoryExpirySettings(
            enabled: _expiryEnabled,
            defaultReminderDays:
                InventoryExpirySettings.normalizeReminderDays(days),
            notifyOwners: _notifyOwners,
            notifyManagers: _notifyManagers,
            notifyStockKeepers: _notifyStockKeepers,
            pushEnabled: _pushEnabled,
            inAppEnabled: _inAppEnabled,
            expiredStockSalePolicy: _salePolicy,
            updatedBy: uid,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory settings saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
