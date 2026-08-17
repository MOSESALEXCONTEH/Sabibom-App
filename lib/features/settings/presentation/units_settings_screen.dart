import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../products/domain/product.dart';

/// Manage default and custom units of measure for products.
class UnitsSettingsScreen extends ConsumerStatefulWidget {
  const UnitsSettingsScreen({super.key});

  @override
  ConsumerState<UnitsSettingsScreen> createState() =>
      _UnitsSettingsScreenState();
}

class _UnitsSettingsScreenState extends ConsumerState<UnitsSettingsScreen> {
  final _controller = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessId = ref
        .watch(currentUserProfileProvider)
        .asData
        ?.value
        ?.activeBusinessId;
    if (businessId == null || businessId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No business has been set up yet.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Units')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .snapshots(),
        builder: (context, snapshot) {
          final custom = _stringList(snapshot.data?.data()?['customUnits']);
          return ListView(
            padding: appSafeScrollPadding(context),
            children: <Widget>[
              Text(
                'Units describe how you sell items (piece, pack, litre, and more). '
                'They appear when you add products and on receipts.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Standard units',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: productUnits
                    .where((u) => u != 'Other')
                    .map((u) => Chip(label: Text(u)))
                    .toList(growable: false),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Custom units',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'Add custom unit',
                        hintText: 'e.g. Bundle',
                      ),
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _add(businessId, custom),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _add(businessId, custom),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (custom.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.straighten_outlined),
                    title: Text('No custom units yet'),
                    subtitle: Text(
                      'Add units unique to your trade, such as crate or yard.',
                    ),
                  ),
                )
              else
                ...custom.map(
                  (unit) => Card(
                    child: ListTile(
                      title: Text(unit),
                      trailing: IconButton(
                        onPressed: _saving
                            ? null
                            : () => _remove(businessId, custom, unit),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(String businessId, List<String> current) async {
    final unit = _controller.text.trim();
    if (unit.isEmpty) return;
    final exists =
        current.any((u) => u.toLowerCase() == unit.toLowerCase()) ||
        productUnits.any((u) => u.toLowerCase() == unit.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That unit already exists.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final next = [...current, unit]..sort();
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .set(<String, Object?>{
            'customUnits': next,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      _controller.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(
    String businessId,
    List<String> current,
    String unit,
  ) async {
    setState(() => _saving = true);
    try {
      final next = current.where((u) => u != unit).toList(growable: false);
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .set(<String, Object?>{
            'customUnits': next,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
