import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/business_setup_data.dart';

class BusinessLocationStep extends StatelessWidget {
  const BusinessLocationStep({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final BusinessSetupData data;
  final void Function({
    String? phoneNumber,
    String? email,
    String? address,
    String? district,
    String? customDistrict,
    String? country,
  })
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Contact and location',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.phoneNumber,
          decoration: const InputDecoration(labelText: 'Business phone number'),
          keyboardType: TextInputType.phone,
          onChanged: (value) => onChanged(phoneNumber: value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.email,
          decoration: const InputDecoration(
            labelText: 'Business email (optional)',
          ),
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) => onChanged(email: value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.address,
          decoration: const InputDecoration(labelText: 'Address'),
          onChanged: (value) => onChanged(address: value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.effectiveDistrict,
          decoration: const InputDecoration(
            labelText: 'State, province, district or region',
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => onChanged(district: value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: data.country,
          decoration: const InputDecoration(labelText: 'Country'),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => onChanged(country: value),
        ),
      ],
    );
  }
}
