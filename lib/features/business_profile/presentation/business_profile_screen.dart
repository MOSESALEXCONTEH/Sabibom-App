import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/image_compression_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../business_setup/domain/business_operating_model.dart';
import '../../team/application/team_providers.dart';
import '../services/pinata_upload_service.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _taglineController = TextEditingController();
  final _websiteController = TextEditingController();
  final _compressor = ImageCompressionService();
  var _isEditing = false;
  var _isSaving = false;
  var _isUploadingLogo = false;
  var _uploadProgress = 0.0;
  var _didPopulate = false;
  String? _logoUrl;
  String? _logoCid;
  CompressedImage? _pendingImage;
  var _operatingModel = BusinessOperatingModel.product;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taglineController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final businessId = profile?.activeBusinessId;
    final isOwner = ref.watch(
      currentBusinessMembershipProvider.select(
        (value) => value.asData?.value?.isOwner == true,
      ),
    );
    if (businessId == null || businessId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No business has been set up yet.')),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .snapshots(),
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
          _nameController.text =
              data['name'] as String? ?? data['businessName'] as String? ?? '';
          _phoneController.text = data['phoneNumber'] as String? ?? '';
          _emailController.text = data['email'] as String? ?? '';
          _addressController.text = data['address'] as String? ?? '';
          _taglineController.text = data['businessTagline'] as String? ?? '';
          _websiteController.text = data['website'] as String? ?? '';
          _logoUrl = data['logoUrl'] as String?;
          _logoCid = data['logoCid'] as String?;
          _operatingModel = BusinessOperatingModel.fromStorage(
            data['operatingModel'],
            businessType: data['businessType'] as String?,
            customBusinessType: data['customBusinessType'] as String?,
          );
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              40,
            ),
            children: <Widget>[
              _LogoSection(
                logoUrl: _logoUrl,
                logoCid: _logoCid,
                pending: _pendingImage != null,
                uploading: _isUploadingLogo,
                progress: _uploadProgress,
                canEdit: _isEditing,
                onPick: () => _pickLogo(),
                onConfirmUpload: () => _uploadLogo(businessId),
                onCancelPending: () => setState(() => _pendingImage = null),
                onRemove: () => _removeLogo(businessId),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your business logo may appear on receipts shared with customers.',
                style: TextStyle(color: AppColors.mutedText, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.lg),
              Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    _field(_nameController, 'Business name', required: true),
                    _field(
                      _phoneController,
                      'Business phone',
                      required: true,
                      type: TextInputType.phone,
                    ),
                    _field(
                      _emailController,
                      'Business email',
                      type: TextInputType.emailAddress,
                    ),
                    _field(
                      _addressController,
                      'Business address',
                      required: true,
                      maxLines: 3,
                    ),
                    _field(_taglineController, 'Tagline'),
                    _field(
                      _websiteController,
                      'Website',
                      type: TextInputType.url,
                    ),
                    DropdownButtonFormField<BusinessOperatingModel>(
                      initialValue: _operatingModel,
                      decoration: const InputDecoration(
                        labelText: 'Business system',
                        helperText:
                            'Controls whether the app uses products, services, or both.',
                      ),
                      items: BusinessOperatingModel.values
                          .map(
                            (model) => DropdownMenuItem(
                              value: model,
                              child: Text(model.displayName),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isEditing && isOwner
                          ? (value) {
                              if (value != null) {
                                setState(() => _operatingModel = value);
                              }
                            }
                          : null,
                    ),
                    if (!isOwner)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Only the business owner can change the business system.',
                            style: TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isEditing) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _isSaving ? null : () => _save(businessId),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _isSaving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType? type,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: controller,
      enabled: _isEditing,
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? '$label is required.'
                : null
          : null,
    ),
  );

  Future<void> _pickLogo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 92,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final compressed = await _compressor.prepareLogo(
        sourceBytes: bytes,
        fileName: picked.name,
        mimeType: picked.mimeType,
      );
      if (!mounted) return;
      setState(() => _pendingImage = compressed);
    } on ImageCompressionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _uploadLogo(String businessId) async {
    final pending = _pendingImage;
    if (pending == null) return;
    setState(() {
      _isUploadingLogo = true;
      _uploadProgress = 0;
    });
    try {
      final result = await ref
          .read(pinataUploadServiceProvider)
          .uploadBusinessLogo(
            businessId: businessId,
            image: pending,
            onProgress: (value) {
              if (mounted) setState(() => _uploadProgress = value);
            },
          );
      if (!mounted) return;
      setState(() {
        _logoUrl = result.logoUrl;
        _logoCid = result.cid;
        _pendingImage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business logo updated.')));
    } on PinataUploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingLogo = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _removeLogo(String businessId) async {
    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .set(<String, Object?>{
          'logoUrl': null,
          'logoCid': null,
          'logoFileName': null,
          'logoMimeType': null,
          'logoUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      _logoUrl = null;
      _logoCid = null;
      _pendingImage = null;
    });
  }

  Future<void> _save(String businessId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .set(<String, Object?>{
            'name': name,
            'normalizedName': name.toLowerCase().replaceAll(
              RegExp(r'\s+'),
              ' ',
            ),
            'phoneNumber': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
            'address': _addressController.text.trim(),
            'businessTagline': _taglineController.text.trim().isEmpty
                ? null
                : _taglineController.text.trim(),
            'website': _websiteController.text.trim().isEmpty
                ? null
                : _websiteController.text.trim(),
            'operatingModel': _operatingModel.storedValue,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          <String, Object?>{'businessName': name},
          SetOptions(merge: true),
        );
      }
      if (mounted) setState(() => _isEditing = false);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not save your business changes. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _LogoSection extends StatelessWidget {
  const _LogoSection({
    required this.logoUrl,
    required this.logoCid,
    required this.pending,
    required this.uploading,
    required this.progress,
    required this.canEdit,
    required this.onPick,
    required this.onConfirmUpload,
    required this.onCancelPending,
    required this.onRemove,
  });

  final String? logoUrl;
  final String? logoCid;
  final bool pending;
  final bool uploading;
  final double progress;
  final bool canEdit;
  final VoidCallback onPick;
  final VoidCallback onConfirmUpload;
  final VoidCallback onCancelPending;
  final VoidCallback onRemove;

  bool get _hasLogo =>
      (logoUrl != null && logoUrl!.trim().isNotEmpty) ||
      (logoCid != null && logoCid!.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            ClipOval(
              child: Container(
                width: 96,
                height: 96,
                color: const Color(0xFFF0ECFF),
                alignment: Alignment.center,
                child: _hasLogo
                    ? AppNetworkImage(
                        url: logoUrl ?? '',
                        cid: logoCid,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(48),
                        fallbackIcon: Icons.storefront_outlined,
                      )
                    : const Icon(
                        Icons.storefront_outlined,
                        size: 36,
                        color: AppColors.primary,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (uploading) ...<Widget>[
              LinearProgressIndicator(value: progress <= 0 ? null : progress),
              const SizedBox(height: 8),
              Text('Uploading ${(progress * 100).clamp(0, 100).toInt()}%'),
            ] else if (pending) ...<Widget>[
              const Text('Image ready. Confirm to upload.'),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancelPending,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirmUpload,
                      child: const Text('Upload logo'),
                    ),
                  ),
                ],
              ),
            ] else if (canEdit) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPick,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Select image'),
                    ),
                  ),
                  if (_hasLogo) ...<Widget>[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove logo',
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
