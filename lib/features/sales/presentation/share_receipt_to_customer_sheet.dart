import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../business_setup/domain/business.dart';
import '../../customers/application/customers_providers.dart';
import '../../customers/domain/customer.dart';
import '../../messaging/customer_messaging_service.dart';
import '../../receipts/data/firestore_receipt_template_repository.dart';
import '../../receipts/domain/receipt_template.dart';
import '../../receipts/services/receipt_pdf_service.dart';
import '../../receipts/services/receipt_share_service.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';

Future<void> showShareReceiptToCustomerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Business business,
  required Sale sale,
  required ReceiptTemplate template,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _ShareReceiptSheet(business: business, sale: sale, template: template),
  );
}

class _ShareReceiptSheet extends ConsumerStatefulWidget {
  const _ShareReceiptSheet({
    required this.business,
    required this.sale,
    required this.template,
  });

  final Business business;
  final Sale sale;
  final ReceiptTemplate template;

  @override
  ConsumerState<_ShareReceiptSheet> createState() => _ShareReceiptSheetState();
}

class _ShareReceiptSheetState extends ConsumerState<_ShareReceiptSheet> {
  final _search = TextEditingController();
  var _busyId = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(
      customersListProvider(widget.business.businessId),
    );
    final query = _search.text.trim().toLowerCase();
    final preferredId = widget.sale.customerId;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Share receipt with customer',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.sale.receiptNumber} · ${formatCurrency(minorToMoney(widget.sale.totalMinor), symbol: widget.business.currency.symbol)}',
                  style: const TextStyle(color: AppColors.mutedText),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search customers',
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: customersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) =>
                        const Center(child: Text('Could not load customers.')),
                    data: (customers) {
                      final list =
                          customers
                              .where((c) => c.isActive && c.hasPhone)
                              .where((c) {
                                if (query.isEmpty) return true;
                                return c.name.toLowerCase().contains(query) ||
                                    (c.phone ?? '').toLowerCase().contains(
                                      query,
                                    );
                              })
                              .toList()
                            ..sort((a, b) {
                              if (a.id == preferredId) return -1;
                              if (b.id == preferredId) return 1;
                              return a.name.compareTo(b.name);
                            });
                      if (list.isEmpty) {
                        return const Center(
                          child: Text('No customers with phone numbers yet.'),
                        );
                      }
                      return ListView.separated(
                        controller: controller,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = list[index];
                          final busy = _busyId == customer.id;
                          return ListTile(
                            title: Text(customer.name),
                            subtitle: Text(customer.phone ?? ''),
                            leading: (customer.photoUrl ?? '').trim().isNotEmpty
                                ? AppNetworkImage(
                                    url: customer.photoUrl!,
                                    width: 40,
                                    height: 40,
                                    borderRadius: BorderRadius.circular(20),
                                    fallbackIcon: Icons.person_outline,
                                  )
                                : CircleAvatar(
                                    backgroundColor: const Color(0xFFF0ECFF),
                                    child: Text(
                                      customer.initials,
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                            trailing: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      if (customer.showWhatsAppBadge)
                                        IconButton(
                                          tooltip: 'WhatsApp PDF',
                                          onPressed: () =>
                                              _shareWhatsApp(customer),
                                          icon: const Icon(
                                            Icons.chat,
                                            color: Color(0xFF25D366),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          tooltip: 'Share PDF (pick WhatsApp)',
                                          onPressed: () =>
                                              _shareWhatsApp(customer),
                                          icon: const Icon(
                                            Icons.picture_as_pdf_outlined,
                                            color: Color(0xFF25D366),
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'SMS summary',
                                        onPressed: () => _shareSms(customer),
                                        icon: const Icon(
                                          Icons.sms_outlined,
                                          color: Color(0xFF5B3DF5),
                                        ),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _smsBody() {
    final sale = widget.sale;
    final business = widget.business;
    return 'SabiBom receipt ${sale.receiptNumber}: Total ${formatCurrency(minorToMoney(sale.totalMinor), symbol: business.currency.symbol)}. Thank you — ${business.name}.';
  }

  Future<void> _shareSms(Customer customer) async {
    setState(() => _busyId = customer.id);
    try {
      await ref
          .read(customerMessagingServiceProvider)
          .openSms(phone: customer.phone!, text: _smsBody());
    } on MessagingException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _shareWhatsApp(Customer customer) async {
    setState(() => _busyId = customer.id);
    try {
      final template = await ReceiptTemplateRepository().getDefaultTemplate(
        widget.business.businessId,
        preferredId: widget.business.defaultReceiptTemplateId,
      );
      final bytes = await ReceiptPdfService().buildPdf(
        sale: widget.sale,
        business: widget.business,
        template: template,
      );
      final file = await ReceiptShareService().writeTempPdf(
        bytes: bytes,
        receiptNumber: widget.sale.receiptNumber,
      );
      await ref
          .read(customerMessagingServiceProvider)
          .sharePdfForWhatsApp(
            pdfFile: file,
            phone: customer.phone!,
            text: _smsBody(),
          );
    } on MessagingException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not prepare the receipt PDF. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }
}
