import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/receipt_settings.dart';

class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.settings});

  final ReceiptSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              settings.businessName.trim().isEmpty
                  ? 'Business Name'
                  : settings.businessName.trim(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              settings.phoneNumber.trim().isEmpty
                  ? 'Phone Number'
                  : settings.phoneNumber.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.mutedTextColor),
            ),
            Text(
              settings.address.trim().isEmpty
                  ? 'Address'
                  : settings.address.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.mutedTextColor),
            ),
            const Divider(height: 24),
            const Text('Sample Item                     15.00'),
            const Text('Sample Item                     10.00'),
            const Divider(height: 24),
            if (settings.showTaxBreakdown)
              const Text('Tax                             0.00'),
            const Text('Total                           25.00'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              settings.footerMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.mutedTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
