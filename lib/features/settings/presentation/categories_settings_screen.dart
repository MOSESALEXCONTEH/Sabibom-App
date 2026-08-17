import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../auth/application/user_profile_provider.dart';

/// Manage product categories used when adding and filtering stock.
class CategoriesSettingsScreen extends ConsumerStatefulWidget {
  const CategoriesSettingsScreen({super.key});

  @override
  ConsumerState<CategoriesSettingsScreen> createState() =>
      _CategoriesSettingsScreenState();
}

class _CategoriesSettingsScreenState
    extends ConsumerState<CategoriesSettingsScreen> {
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
      appBar: AppBar(title: const Text('Categories')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .snapshots(),
        builder: (context, businessSnap) {
          final saved = _stringList(
            businessSnap.data?.data()?['productCategories'],
          );
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('businesses')
                .doc(businessId)
                .collection('products')
                .where('status', isEqualTo: 'active')
                .snapshots(),
            builder: (context, productsSnap) {
              final used = <String>{};
              for (final doc in productsSnap.data?.docs ?? const []) {
                final name =
                    (doc.data()['categoryName'] as String?)?.trim() ?? '';
                if (name.isNotEmpty) used.add(name);
              }
              final all = {...saved, ...used}.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

              return ListView(
                padding: appSafeScrollPadding(context),
                children: <Widget>[
                  Text(
                    'Categories help you organize products on the Products tab '
                    'and speed up adding new items.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            labelText: 'New category',
                            hintText: 'e.g. Drinks',
                          ),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) => _add(businessId, saved),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _add(businessId, saved),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (all.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.category_outlined),
                        title: Text('No categories yet'),
                        subtitle: Text(
                          'Add categories here, or type one when creating a product.',
                        ),
                      ),
                    )
                  else
                    ...all.map((name) {
                      final isSaved = saved.contains(name);
                      final inUse = used.contains(name);
                      return Card(
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text(
                            [
                              if (isSaved) 'Saved',
                              if (inUse) 'Used on products',
                              if (!isSaved && inUse) 'From products',
                            ].join(' · '),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove from saved list',
                            onPressed: !isSaved || _saving
                                ? null
                                : () => _remove(businessId, saved, name),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(String businessId, List<String> current) async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (current.any((c) => c.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That category already exists.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final next = [...current, name]..sort();
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .set(<String, Object?>{
            'productCategories': next,
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
    String name,
  ) async {
    setState(() => _saving = true);
    try {
      final next = current.where((c) => c != name).toList(growable: false);
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .set(<String, Object?>{
            'productCategories': next,
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
