import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  var _isEditing = false;
  var _isSaving = false;
  var _didPopulate = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final businessId = profile?.activeBusinessId;
    if (businessId == null || businessId.isEmpty) {
      return const Scaffold(body: Center(child: Text('No business has been set up yet.')));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('businesses').doc(businessId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data();
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('This business is no longer available.')),
          );
        }
        if (!_didPopulate) {
          _didPopulate = true;
          _nameController.text = data['name'] as String? ?? data['businessName'] as String? ?? '';
          _phoneController.text = data['phoneNumber'] as String? ?? '';
          _emailController.text = data['email'] as String? ?? '';
          _addressController.text = data['address'] as String? ?? '';
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Business Profile'),
            actions: <Widget>[
              if (!_isEditing)
                IconButton(
                  tooltip: 'Edit business profile',
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: <Widget>[
              Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    _field(_nameController, 'Business name', required: true),
                    _field(_phoneController, 'Business phone', required: true, type: TextInputType.phone),
                    _field(_emailController, 'Business email', type: TextInputType.emailAddress),
                    _field(_addressController, 'Business address', required: true, maxLines: 3),
                  ],
                ),
              ),
              if (_isEditing) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _isSaving ? null : () => _save(businessId),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _isSaving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save changes'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController controller, String label, {bool required = false, TextInputType? type, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: controller,
      enabled: _isEditing,
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: required ? (value) => value == null || value.trim().isEmpty ? '$label is required.' : null : null,
    ),
  );

  Future<void> _save(String businessId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('businesses').doc(businessId).set(<String, Object?>{
        'name': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          <String, Object?>{'businessName': _nameController.text.trim()},
          SetOptions(merge: true),
        );
      }
      if (mounted) setState(() => _isEditing = false);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not save your business changes. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}