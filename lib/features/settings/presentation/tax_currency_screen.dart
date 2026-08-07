import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../business_setup/domain/business_setup_data.dart';

/// Edit tax and currency used for sales totals and receipts.
class TaxCurrencyScreen extends ConsumerStatefulWidget {
  const TaxCurrencyScreen({super.key});

  @override
  ConsumerState<TaxCurrencyScreen> createState() => _TaxCurrencyScreenState();
}

class _TaxCurrencyScreenState extends ConsumerState<TaxCurrencyScreen> {
  final _taxController = TextEditingController();
  var _taxEnabled = false;
  var _currency = CurrencyConfig.sle;
  var _financialYearStartMonth = 'January';
  var _hydrated = false;
  var _saving = false;

  static const _currencies = <CurrencyConfig>[
    CurrencyConfig.sle,
    CurrencyConfig(code: 'USD', name: 'US Dollar', symbol: r'$'),
    CurrencyConfig(code: 'GHS', name: 'Ghanaian Cedi', symbol: 'GH₵'),
    CurrencyConfig(code: 'NGN', name: 'Nigerian Naira', symbol: '₦'),
    CurrencyConfig(code: 'GBP', name: 'British Pound', symbol: '£'),
    CurrencyConfig(code: 'EUR', name: 'Euro', symbol: '€'),
  ];

  @override
  void dispose() {
    _taxController.dispose();
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null && !_hydrated) {
          _hydrated = true;
          _taxEnabled = data['taxEnabled'] as bool? ?? false;
          _taxController.text =
              ((data['taxPercentage'] as num?)?.toDouble() ?? 0).toString();
          _financialYearStartMonth =
              data['financialYearStartMonth'] as String? ?? 'January';
          final code = data['currencyCode'] as String? ?? CurrencyConfig.sle.code;
          _currency = _currencies.firstWhere(
            (c) => c.code == code,
            orElse: () => CurrencyConfig(
              code: code,
              name: data['currencyName'] as String? ?? code,
              symbol: data['currencySymbol'] as String? ?? code,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Tax and Currency')),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: <Widget>[
              Text(
                'These settings control how money and tax appear on sales, '
                'receipts, and reports.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _currency.code,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: _currencies
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.code,
                        child: Text(
                          '${c.code} (${c.symbol}) — ${c.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                selectedItemBuilder: (context) => _currencies
                    .map(
                      (c) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${c.code} (${c.symbol})',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (code) {
                  if (code == null) return;
                  setState(() {
                    _currency = _currencies.firstWhere((c) => c.code == code);
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Charge tax on sales'),
                subtitle: const Text(
                  'When enabled, tax is calculated at checkout and shown on receipts.',
                ),
                value: _taxEnabled,
                onChanged: (value) => setState(() => _taxEnabled = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _taxController,
                enabled: _taxEnabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tax percentage',
                  suffixText: '%',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _financialYearStartMonth,
                decoration: const InputDecoration(
                  labelText: 'Financial year starts',
                ),
                items: BusinessSetupData.months
                    .map(
                      (month) =>
                          DropdownMenuItem(value: month, child: Text(month)),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _financialYearStartMonth = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : () => _save(businessId),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(String businessId) async {
    final tax = double.tryParse(_taxController.text.trim()) ?? 0;
    if (_taxEnabled && (tax < 0 || tax > 100 || !tax.isFinite)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a tax percentage between 0 and 100.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('businesses').doc(businessId).set(
        <String, Object?>{
          'currencyCode': _currency.code,
          'currencyName': _currency.name,
          'currencySymbol': _currency.symbol,
          'taxEnabled': _taxEnabled,
          'taxPercentage': _taxEnabled ? tax : 0,
          'financialYearStartMonth': _financialYearStartMonth,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tax and currency updated.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
