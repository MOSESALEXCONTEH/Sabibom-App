import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/business_setup_data.dart';
import '../../domain/business_operating_model.dart';
import '../widgets/business_type_selector.dart';

class BusinessDetailsStep extends StatelessWidget {
  const BusinessDetailsStep({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final BusinessSetupData data;
  final void Function({
    String? businessName,
    String? businessType,
    BusinessOperatingModel? operatingModel,
    String? customBusinessType,
    String? ownerName,
    String? logoPath,
    bool clearLogoPath,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Business details',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Logo upload will be enabled soon.'),
              ),
            );
          },
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.borderColor),
              color: context.surfaceColor,
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          initialValue: data.businessName,
          decoration: const InputDecoration(labelText: 'Business name'),
          maxLength: 80,
          onChanged: (value) => onChanged(businessName: value),
        ),
        const SizedBox(height: AppSpacing.md),
        BusinessTypeSelector(
          value: data.businessType,
          options: BusinessSetupData.businessTypes,
          onChanged: (value) => onChanged(businessType: value ?? ''),
        ),
        if (data.businessType == 'Other') ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: data.customBusinessType,
            decoration: const InputDecoration(
              labelText: 'Custom business type',
            ),
            onChanged: (value) => onChanged(customBusinessType: value),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'How does this business operate?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This controls the tools and wording shown in the app.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final model in BusinessOperatingModel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: data.operatingModel == model
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(operatingModel: model),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        data.operatingModel == model
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: data.operatingModel == model
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              model.displayName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              model.description,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.ownerName,
          decoration: const InputDecoration(labelText: 'Owner name'),
          onChanged: (value) => onChanged(ownerName: value),
        ),
      ],
    );
  }
}
