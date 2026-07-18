import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/business_setup_data.dart';
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
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFD0D5DD)),
              color: Colors.white,
            ),
            child: const Icon(Icons.storefront_outlined, size: 38),
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
