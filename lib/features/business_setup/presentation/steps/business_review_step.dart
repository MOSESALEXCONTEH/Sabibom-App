import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/business_setup_data.dart';

class BusinessReviewStep extends StatelessWidget {
  const BusinessReviewStep({
    super.key,
    required this.data,
    required this.onEdit,
  });

  final BusinessSetupData data;
  final ValueChanged<BusinessSetupStep> onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Review and finish',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewCard(
          title: 'Business details',
          lines: <String>[
            'Business name: ${data.businessName.trim()}',
            'Business type: ${data.effectiveBusinessType}',
            'Owner: ${data.ownerName.trim()}',
          ],
          onEdit: () => onEdit(BusinessSetupStep.businessDetails),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReviewCard(
          title: 'Contact and location',
          lines: <String>[
            'Phone: ${data.phoneNumber.trim()}',
            'Address: ${data.address.trim()}',
            'District: ${data.effectiveDistrict}',
          ],
          onEdit: () => onEdit(BusinessSetupStep.contactAndLocation),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReviewCard(
          title: 'Financial settings',
          lines: <String>[
            'Currency: ${data.currency.code} (${data.currency.symbol})',
            'Tax: ${data.taxEnabled ? '${data.taxPercentage}%' : 'Disabled'}',
            'Financial year start: ${data.financialYearStartMonth}',
          ],
          onEdit: () => onEdit(BusinessSetupStep.financialSettings),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReviewCard(
          title: 'Receipt settings',
          lines: <String>[
            'Receipt name: ${data.receiptSettings.businessName.trim()}',
            'Phone: ${data.receiptSettings.phoneNumber.trim()}',
            'Footer: ${data.receiptSettings.footerMessage}',
          ],
          onEdit: () => onEdit(BusinessSetupStep.receiptSettings),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.lines,
    required this.onEdit,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
              ],
            ),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}
