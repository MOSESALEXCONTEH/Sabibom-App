import 'package:flutter/material.dart';

class BusinessTypeSelector extends StatelessWidget {
  const BusinessTypeSelector({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      items: options
          .map(
            (type) => DropdownMenuItem<String>(value: type, child: Text(type)),
          )
          .toList(growable: false),
      onChanged: onChanged,
      decoration: const InputDecoration(labelText: 'Business type'),
    );
  }
}
