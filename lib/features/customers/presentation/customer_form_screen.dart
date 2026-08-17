import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/image_compression_service.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../../../core/sync/pending_media_store.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../business_profile/services/pinata_upload_service.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/customers_providers.dart';
import '../data/customers_repository.dart';
import '../domain/customer.dart';

class AddCustomerScreen extends ConsumerWidget {
  const AddCustomerScreen({super.key, this.returnToCheckout = false});

  final bool returnToCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CustomerFormScaffold(
      mode: _Mode.create,
      returnToCheckout: returnToCheckout,
    );
  }
}

class EditCustomerScreen extends ConsumerWidget {
  const EditCustomerScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CustomerFormScaffold(mode: _Mode.edit, customerId: customerId);
  }
}

enum _Mode { create, edit }

class _CustomerFormScaffold extends ConsumerStatefulWidget {
  const _CustomerFormScaffold({
    required this.mode,
    this.customerId,
    this.returnToCheckout = false,
  });

  final _Mode mode;
  final String? customerId;
  final bool returnToCheckout;

  @override
  ConsumerState<_CustomerFormScaffold> createState() =>
      _CustomerFormScaffoldState();
}

class _CustomerFormScaffoldState extends ConsumerState<_CustomerFormScaffold> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  var _submitting = false;
  var _hydrated = false;
  var _usesWhatsApp = false;
  CompressedImage? _selectedPhoto;
  String? _photoUrl;
  String? _photoCid;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(Customer customer) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = customer.name;
    _phone.text = customer.phone ?? '';
    _email.text = customer.email ?? '';
    _address.text = customer.address ?? '';
    _notes.text = customer.notes ?? '';
    _usesWhatsApp = customer.usesWhatsApp;
    _photoUrl = customer.photoUrl;
    _photoCid = customer.photoCid;
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up or select a business to continue.')),
      );
    }
    final businessId = active.business.businessId;

    if (widget.mode == _Mode.edit) {
      final detail = ref.watch(
        customerDetailProvider((businessId, widget.customerId!)),
      );
      return detail.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Customer')),
          body: const Center(child: Text('Could not load customer.')),
        ),
        data: (customer) {
          if (customer == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Edit Customer')),
              body: const Center(child: Text('Customer not found.')),
            );
          }
          _hydrate(customer);
          return _form(businessId);
        },
      );
    }
    return _form(businessId);
  }

  Widget _form(String businessId) {
    final isEdit = widget.mode == _Mode.edit;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Customer' : 'Add Customer')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: appSafeScrollPadding(
              context,
              left: 20,
              top: 12,
              right: 20,
            ),
            children: <Widget>[
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    _CustomerPhoto(
                      bytes: _selectedPhoto?.bytes,
                      url: _photoUrl,
                      fallbackLabel: _name.text.trim().isEmpty
                          ? '?'
                          : _name.text.trim().substring(0, 1).toUpperCase(),
                    ),
                    Positioned(
                      right: -8,
                      bottom: -8,
                      child: IconButton.filledTonal(
                        tooltip: 'Add customer photo',
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name *'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if ((value ?? '').trim().length < 2) {
                    return 'Enter at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return null;
                  if (raw.replaceAll(RegExp(r'\D'), '').length < 7) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return null;
                  if (!raw.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Uses WhatsApp'),
                subtitle: const Text(
                  'Show the WhatsApp logo for this customer when messaging.',
                ),
                value: _usesWhatsApp,
                onChanged: (value) => setState(() => _usesWhatsApp = value),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(businessId),
                child: Text(
                  _submitting
                      ? 'Saving...'
                      : (isEdit ? 'Save changes' : 'Create customer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String businessId, {bool allowDuplicate = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    setState(() => _submitting = true);
    try {
      final isOnline = ref.read(isOnlineProvider).asData?.value ?? true;
      if (_selectedPhoto != null && isOnline) {
        final uploaded = await ref
            .read(pinataUploadServiceProvider)
            .uploadCustomerPhoto(
              businessId: businessId,
              image: _selectedPhoto!,
            );
        _photoUrl = uploaded.logoUrl;
        _photoCid = uploaded.cid;
      }
      final draft = CustomerDraft(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        photoUrl: _photoUrl,
        photoCid: _photoCid,
        usesWhatsApp: _usesWhatsApp,
      );
      final repo = ref.read(customersRepositoryProvider);
      late final String id;
      if (widget.mode == _Mode.create) {
        id = await repo.createCustomer(
          businessId,
          draft,
          allowDuplicatePhone: allowDuplicate,
          branchId: branchId,
          queueWhenOffline: !isOnline,
        );
      } else {
        id = widget.customerId!;
        await repo.updateCustomer(businessId, id, draft, branchId: branchId);
      }
      if (_selectedPhoto != null && !isOnline) {
        final localPath = await persistPendingImage(
          id: 'customer_$id',
          image: _selectedPhoto!,
        );
        await ref
            .read(offlineMutationQueueProvider)
            .enqueue(
              id: 'media_customer_$id',
              type: OfflineMutationType.mediaUpload,
              businessId: businessId,
              payload: <String, dynamic>{
                'purpose': 'customer_photo',
                'collection': 'customers',
                'recordId': id,
                'localPath': localPath,
                'fileName': _selectedPhoto!.fileName,
                'mimeType': _selectedPhoto!.mimeType,
                'width': _selectedPhoto!.width,
                'height': _selectedPhoto!.height,
              },
            );
      }
      if (!mounted) return;
      if (!isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer saved. Waiting to sync.')),
        );
      }
      if (widget.mode == _Mode.create) {
        if (widget.returnToCheckout) {
          context.pop(id);
        } else {
          context.goNamed(
            AppRouteNames.customerDetails,
            pathParameters: <String, String>{'customerId': id},
          );
        }
      } else {
        context.pop();
      }
    } on DuplicateCustomerException catch (error) {
      if (!mounted) return;
      final openExisting = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Customer already exists'),
          content: Text(
            'Another customer already uses this phone number: ${error.existing.name}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open existing'),
            ),
          ],
        ),
      );
      if (openExisting == true && mounted) {
        context.goNamed(
          AppRouteNames.customerDetails,
          pathParameters: <String, String>{'customerId': error.existing.id},
        );
      }
    } on CustomerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
    } on PinataUploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (picked == null) return;
      final prepared = await ImageCompressionService().prepareLogo(
        sourceBytes: await picked.readAsBytes(),
        fileName: picked.name,
        mimeType: picked.mimeType,
      );
      if (mounted) setState(() => _selectedPhoto = prepared);
    } on ImageCompressionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _CustomerPhoto extends StatelessWidget {
  const _CustomerPhoto({this.bytes, this.url, required this.fallbackLabel});

  final Uint8List? bytes;
  final String? url;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 42,
      child: Text(fallbackLabel, style: const TextStyle(fontSize: 28)),
    );
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(bytes!, width: 84, height: 84, fit: BoxFit.cover),
      );
    }
    if ((url ?? '').trim().isNotEmpty) {
      return AppNetworkImage(
        url: url!,
        width: 84,
        height: 84,
        borderRadius: BorderRadius.circular(42),
        fallbackIcon: Icons.person_outline,
      );
    }
    return fallback;
  }
}
