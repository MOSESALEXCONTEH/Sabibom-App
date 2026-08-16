import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/image_compression_service.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../../../core/sync/pending_media_store.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/barcode_scanner_screen.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../business_profile/services/pinata_upload_service.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../business_setup/application/business_experience_providers.dart';
import '../../inventory/domain/product_profit_calculator.dart';
import '../../inventory/domain/stock_quantity_rules.dart';
import '../../sales/domain/sale_models.dart';
import '../application/products_providers.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';

class AddProductScreen extends ConsumerWidget {
  const AddProductScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _ProductFormScaffold(mode: _ProductFormMode.create);
  }
}

class EditProductScreen extends ConsumerWidget {
  const EditProductScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ProductFormScaffold(
      mode: _ProductFormMode.edit,
      productId: productId,
    );
  }
}

enum _ProductFormMode { create, edit }

class _ProductFormScaffold extends ConsumerStatefulWidget {
  const _ProductFormScaffold({required this.mode, this.productId});

  final _ProductFormMode mode;
  final String? productId;

  @override
  ConsumerState<_ProductFormScaffold> createState() =>
      _ProductFormScaffoldState();
}

class _ProductFormScaffoldState extends ConsumerState<_ProductFormScaffold> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _sellingPrice = TextEditingController();
  final _costPrice = TextEditingController();
  final _openingStock = TextEditingController(text: '0');
  final _lowStock = TextEditingController(text: '5');
  final _customUnit = TextEditingController();

  var _trackStock = true;
  var _tracksExpiry = false;
  var _initialExpiryDateKnown = false;
  DateTime? _initialExpiryDate;
  var _expiryReminderDays = 30;
  var _unit = 'Piece';
  var _status = ProductStatus.active;
  var _submitting = false;
  var _hydrated = false;
  CompressedImage? _selectedImage;
  String? _imageUrl;
  String? _imageCid;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _category.dispose();
    _description.dispose();
    _sellingPrice.dispose();
    _costPrice.dispose();
    _openingStock.dispose();
    _lowStock.dispose();
    _customUnit.dispose();
    super.dispose();
  }

  void _hydrate(Product product) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = product.name;
    _sku.text = product.sku ?? '';
    _barcode.text = product.barcode ?? '';
    _category.text = product.categoryName ?? '';
    _description.text = product.description ?? '';
    _sellingPrice.text = minorToMoney(
      product.sellingPriceMinor,
    ).toStringAsFixed(2);
    _costPrice.text = product.costPriceMinor == 0
        ? ''
        : minorToMoney(product.costPriceMinor).toStringAsFixed(2);
    _lowStock.text = product.lowStockThreshold.toString();
    _trackStock = product.trackStock;
    _tracksExpiry = product.tracksExpiry;
    _expiryReminderDays = product.defaultExpiryReminderDays;
    _status = product.status;
    _imageUrl = product.imageUrl;
    _imageCid = product.imageCid;
    if (productUnits.contains(product.unit)) {
      _unit = product.unit;
    } else {
      _unit = 'Other';
      _customUnit.text = product.unit;
    }
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

    if (widget.mode == _ProductFormMode.create && !_hydrated) {
      _hydrated = true;
      if (active.business.operatingModel.name == 'service') {
        _trackStock = false;
        _unit = 'Service';
      }
    }

    if (widget.mode == _ProductFormMode.edit) {
      final detail = ref.watch(
        productDetailProvider((businessId, widget.productId!)),
      );
      return detail.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Product')),
          body: const Center(child: Text('Could not load this product.')),
        ),
        data: (product) {
          if (product == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Edit Product')),
              body: const Center(child: Text('Product not found.')),
            );
          }
          _hydrate(product);
          return _buildForm(context, businessId);
        },
      );
    }

    return _buildForm(context, businessId);
  }

  Widget _buildForm(BuildContext context, String businessId) {
    final isEdit = widget.mode == _ProductFormMode.edit;
    final terminology = ref.watch(currentBusinessTerminologyProvider);
    final capabilities = ref.watch(currentBusinessCapabilitiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('${isEdit ? 'Edit' : 'Add'} ${terminology.product}'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    _ProductPhoto(bytes: _selectedImage?.bytes, url: _imageUrl),
                    Positioned(
                      right: -8,
                      bottom: -8,
                      child: IconButton.filledTonal(
                        tooltip: 'Add product image',
                        onPressed: _pickProductImage,
                        icon: const Icon(Icons.add_a_photo_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '${terminology.product} name *',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if ((value ?? '').trim().length < 2) {
                    return 'Enter at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sku,
                decoration: const InputDecoration(labelText: 'SKU'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode',
                    onPressed: () async {
                      final value = await scanBarcode(context);
                      if (value != null && mounted) {
                        setState(() => _barcode.text = value);
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sellingPrice,
                decoration: const InputDecoration(
                  labelText: 'Selling price (Le) *',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final amount = double.tryParse((value ?? '').trim());
                  if (amount == null) return 'Enter a valid price';
                  if (amount < 0) return 'Price cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costPrice,
                decoration: const InputDecoration(labelText: 'Cost price (Le)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return null;
                  final amount = double.tryParse(raw);
                  if (amount == null) return 'Enter a valid cost';
                  if (amount < 0) return 'Cost cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (capabilities.managesInventory)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track stock'),
                  value: _trackStock,
                  onChanged: (value) => setState(() => _trackStock = value),
                ),
              if (_trackStock && !isEdit) ...<Widget>[
                TextFormField(
                  controller: _openingStock,
                  decoration: const InputDecoration(
                    labelText: 'Opening stock *',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final amount = double.tryParse((value ?? '').trim());
                    return StockQuantityRules.validate(
                      quantity: amount,
                      unit: _selectedUnit,
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (_trackStock)
                TextFormField(
                  controller: _lowStock,
                  decoration: const InputDecoration(
                    labelText: 'Low-stock alert quantity',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final amount = double.tryParse((value ?? '').trim());
                    if (amount == null) return 'Enter a valid threshold';
                    if (amount < 0) return 'Threshold cannot be negative';
                    return null;
                  },
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: productUnits
                    .map(
                      (unit) => DropdownMenuItem<String>(
                        value: unit,
                        child: Text(unit),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _unit = value);
                    _formKey.currentState?.validate();
                  }
                },
              ),
              if (_unit == 'Other') ...<Widget>[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customUnit,
                  decoration: const InputDecoration(labelText: 'Custom unit'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a custom unit';
                    }
                    return null;
                  },
                ),
              ],
              if (_trackStock && !isEdit) ...<Widget>[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('This product has an expiry date'),
                  subtitle: const Text(
                    'Turn this on for food, drinks, cosmetics, medicine and other products that expire.',
                  ),
                  value: _tracksExpiry,
                  onChanged: (value) {
                    setState(() {
                      _tracksExpiry = value;
                      if (!value) {
                        _initialExpiryDateKnown = false;
                        _initialExpiryDate = null;
                      }
                    });
                  },
                ),
                if (_tracksExpiry) ...<Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Initial Stock Expiry Date'),
                    subtitle: Text(
                      _initialExpiryDateKnown && _initialExpiryDate != null
                          ? DateFormat.yMMMd().format(_initialExpiryDate!)
                          : 'No expiry date entered',
                    ),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: _selectInitialExpiryDate,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Expiry date unknown'),
                    subtitle: const Text(
                      'Use this only when the expiry date is genuinely unavailable.',
                    ),
                    value: !_initialExpiryDateKnown,
                    onChanged: (value) {
                      if (value == false) {
                        _selectInitialExpiryDate();
                      } else {
                        setState(() {
                          _initialExpiryDateKnown = false;
                          _initialExpiryDate = null;
                        });
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _expiryReminderDays,
                    decoration: const InputDecoration(
                      labelText: 'Expiry reminder',
                    ),
                    items: const <int>[30, 14, 7, 3, 1, 0]
                        .map(
                          (days) => DropdownMenuItem<int>(
                            value: days,
                            child: Text(
                              days == 0 ? 'On expiry day' : '$days days before',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _expiryReminderDays = value);
                      }
                    },
                  ),
                  if (_openingQuantity > 0 && !_initialExpiryDateKnown)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'The opening batch will be saved with an unknown expiry date.',
                      ),
                    ),
                ],
              ],
              if (!isEdit) ...<Widget>[
                const SizedBox(height: 16),
                _buildProfitPreview(context),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<ProductStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: ProductStatus.values
                    .map(
                      (status) => DropdownMenuItem<ProductStatus>(
                        value: status,
                        child: Text(
                          status == ProductStatus.active
                              ? 'Active'
                              : 'Archived',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              if (isEdit) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'Stock quantity is changed from Adjust Stock so inventory history stays auditable.',
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(businessId),
                child: Text(
                  _submitting
                      ? 'Saving...'
                      : (isEdit
                            ? 'Save changes'
                            : 'Create ${terminology.product.toLowerCase()}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectedUnit =>
      _unit == 'Other' ? _customUnit.text.trim() : _unit;

  double get _openingQuantity =>
      double.tryParse(_openingStock.text.trim()) ?? 0;

  Widget _buildProfitPreview(BuildContext context) {
    final summary = ProductProfitCalculator.calculate(
      currentStock: _trackStock ? _openingQuantity : 0,
      currentUnitCostMinor: _costPrice.text.trim().isEmpty
          ? 0
          : moneyToMinor(_costPrice.text.trim()),
      currentSellingPriceMinor: moneyToMinor(_sellingPrice.text.trim()),
    );
    final remainingLabel = summary.hasPotentialLoss
        ? 'Estimated potential gross loss'
        : 'Estimated potential gross profit';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current stock estimate',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _PreviewRow(
              label: 'Profit per $_selectedUnit',
              value: formatCurrency(
                minorToMoney(summary.unitPotentialProfitMinor),
              ),
            ),
            _PreviewRow(
              label: 'Stock cost',
              value: formatCurrency(minorToMoney(summary.stockCostValueMinor)),
            ),
            _PreviewRow(
              label: 'Expected revenue',
              value: formatCurrency(
                minorToMoney(summary.expectedStockRevenueMinor),
              ),
            ),
            _PreviewRow(
              label: remainingLabel,
              value: formatCurrency(
                minorToMoney(summary.potentialProfitRemainingMinor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This is an estimate, not guaranteed profit. Discounts, returns, losses and price changes can affect it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectInitialExpiryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _initialExpiryDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (selected == null || !mounted) return;
    final today = DateTime(now.year, now.month, now.day);
    if (selected.isBefore(today)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Stock is already expired'),
          content: const Text(
            'This date has already passed. Confirm that the stock is already expired.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _initialExpiryDate = selected;
      _initialExpiryDateKnown = true;
    });
  }

  Future<void> _submit(String businessId) async {
    if (!_formKey.currentState!.validate()) return;
    final barcode = _barcode.text.trim();
    if (barcode.isNotEmpty) {
      final products = ref.read(productsListProvider(businessId)).asData?.value;
      final duplicate = hasDuplicateBarcode(
        products: products ?? const <Product>[],
        barcode: barcode,
        excludingProductId: widget.productId,
      );
      if (duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This barcode is already assigned to a product.'),
          ),
        );
        return;
      }
    }
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    setState(() => _submitting = true);
    try {
      final isOnline = ref.read(isOnlineProvider).asData?.value ?? true;
      if (_selectedImage != null && isOnline) {
        final uploaded = await ref
            .read(pinataUploadServiceProvider)
            .uploadProductImage(businessId: businessId, image: _selectedImage!);
        _imageUrl = uploaded.logoUrl;
        _imageCid = uploaded.cid;
      }
      final draft = ProductDraft(
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        barcode: _barcode.text.trim(),
        description: _description.text.trim(),
        categoryName: _category.text.trim().isEmpty
            ? null
            : _category.text.trim(),
        imageUrl: _imageUrl,
        imageCid: _imageCid,
        sellingPriceMinor: moneyToMinor(_sellingPrice.text.trim()),
        costPriceMinor: _costPrice.text.trim().isEmpty
            ? 0
            : moneyToMinor(_costPrice.text.trim()),
        trackStock: _trackStock,
        quantity: _trackStock
            ? (double.tryParse(_openingStock.text.trim()) ?? 0)
            : 0,
        lowStockThreshold: _trackStock
            ? (double.tryParse(_lowStock.text.trim()) ?? 0)
            : 0,
        unit: _unit == 'Other' ? _customUnit.text.trim() : _unit,
        status: _status,
        tracksExpiry: _tracksExpiry,
        defaultExpiryReminderDays: _expiryReminderDays,
        initialStockExpiryDate: _initialExpiryDate,
        initialStockExpiryDateKnown: _tracksExpiry && _initialExpiryDateKnown,
      );
      final repo = ref.read(productsRepositoryProvider);
      late final String id;
      if (widget.mode == _ProductFormMode.create) {
        id = await repo.createProduct(
          businessId,
          draft,
          branchId: branchId,
          queueWhenOffline: !isOnline,
        );
      } else {
        id = widget.productId!;
        await repo.updateProduct(
          businessId,
          widget.productId!,
          draft,
          branchId: branchId,
        );
      }
      if (_selectedImage != null && !isOnline) {
        final localPath = await persistPendingImage(
          id: 'product_$id',
          image: _selectedImage!,
        );
        await ref
            .read(offlineMutationQueueProvider)
            .enqueue(
              id: 'media_product_$id',
              type: OfflineMutationType.mediaUpload,
              businessId: businessId,
              payload: <String, dynamic>{
                'purpose': 'product_image',
                'collection': 'products',
                'recordId': id,
                'localPath': localPath,
                'fileName': _selectedImage!.fileName,
                'mimeType': _selectedImage!.mimeType,
                'width': _selectedImage!.width,
                'height': _selectedImage!.height,
              },
            );
      }
      if (!mounted) return;
      if (!isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product saved. Waiting to sync.')),
        );
      }
      if (widget.mode == _ProductFormMode.create) {
        if (isOnline) {
          context.goNamed(
            AppRouteNames.productDetails,
            pathParameters: <String, String>{'productId': id},
          );
        } else {
          context.pop();
        }
      } else {
        context.pop();
      }
    } on ProductException catch (error) {
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

  Future<void> _pickProductImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take product photo'),
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
      if (mounted) setState(() => _selectedImage = prepared);
    } on ImageCompressionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _ProductPhoto extends StatelessWidget {
  const _ProductPhoto({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(bytes!, width: 112, height: 112, fit: BoxFit.cover),
      );
    }
    if ((url ?? '').trim().isNotEmpty) {
      return AppNetworkImage(
        url: url!,
        width: 112,
        height: 112,
        borderRadius: BorderRadius.circular(12),
        fallbackIcon: Icons.inventory_2_outlined,
      );
    }
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.inventory_2_outlined, size: 42),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
