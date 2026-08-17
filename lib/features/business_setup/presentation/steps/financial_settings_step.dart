import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/business_setup_data.dart';

class FinancialSettingsStep extends StatelessWidget {
  const FinancialSettingsStep({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final BusinessSetupData data;
  final void Function({
    CurrencyConfig? currency,
    String? timezone,
    bool? taxEnabled,
    double? taxPercentage,
    String? financialYearStartMonth,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Financial settings',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: data.currency.code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Business currency'),
          items: CurrencyConfig.supported
              .map(
                (currency) => DropdownMenuItem(
                  value: currency.code,
                  child: Text(
                    '${currency.code} (${currency.symbol}) - ${currency.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (code) {
            if (code == null) return;
            onChanged(
              currency: CurrencyConfig.supported.firstWhere(
                (currency) => currency.code == code,
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: data.timezone,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Business timezone'),
          items: BusinessSetupData.timezones
              .map(
                (timezone) => DropdownMenuItem(
                  value: timezone,
                  child: Text(timezone, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (timezone) => onChanged(timezone: timezone),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: data.taxEnabled,
          title: const Text('Enable tax'),
          onChanged: (value) => onChanged(taxEnabled: value),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          initialValue: data.taxPercentage.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: data.taxEnabled,
          decoration: const InputDecoration(labelText: 'Tax percentage'),
          onChanged: (value) => onChanged(
            taxPercentage: double.tryParse(value) ?? data.taxPercentage,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: data.financialYearStartMonth,
          decoration: const InputDecoration(labelText: 'Financial year start'),
          items: BusinessSetupData.months
              .map(
                (month) => DropdownMenuItem(value: month, child: Text(month)),
              )
              .toList(growable: false),
          onChanged: (value) => onChanged(financialYearStartMonth: value),
        ),
      ],
    );
  }
}
