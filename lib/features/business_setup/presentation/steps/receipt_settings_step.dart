import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/receipt_settings.dart';
import '../widgets/receipt_preview.dart';

class ReceiptSettingsStep extends StatelessWidget {
  const ReceiptSettingsStep({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ReceiptSettings settings;
  final ValueChanged<ReceiptSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Receipt settings',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: settings.businessName,
          decoration: const InputDecoration(labelText: 'Receipt business name'),
          onChanged: (value) =>
              onChanged(settings.copyWith(businessName: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: settings.phoneNumber,
          decoration: const InputDecoration(labelText: 'Receipt phone number'),
          onChanged: (value) =>
              onChanged(settings.copyWith(phoneNumber: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: settings.address,
          decoration: const InputDecoration(labelText: 'Receipt address'),
          onChanged: (value) => onChanged(settings.copyWith(address: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: settings.footerMessage,
          decoration: const InputDecoration(
            labelText: 'Receipt footer message',
          ),
          onChanged: (value) =>
              onChanged(settings.copyWith(footerMessage: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.showLogo,
          title: const Text('Show business logo on receipt'),
          onChanged: (value) => onChanged(settings.copyWith(showLogo: value)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.showCashierName,
          title: const Text('Show cashier name'),
          onChanged: (value) =>
              onChanged(settings.copyWith(showCashierName: value)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.showCustomerName,
          title: const Text('Show customer name'),
          onChanged: (value) =>
              onChanged(settings.copyWith(showCustomerName: value)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.showTaxBreakdown,
          title: const Text('Show tax breakdown'),
          onChanged: (value) =>
              onChanged(settings.copyWith(showTaxBreakdown: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        ReceiptPreview(settings: settings),
      ],
    );
  }
}
