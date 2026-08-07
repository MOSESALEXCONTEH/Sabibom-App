import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/sync/record_sync_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../receipts/data/firestore_receipt_template_repository.dart';
import '../../receipts/domain/receipt_template.dart';
import '../../receipts/services/receipt_pdf_service.dart';
import '../../receipts/services/receipt_share_service.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/approval_models.dart';
import '../../team/domain/team_exception.dart';
import '../application/sale_void_service.dart';
import '../application/sales_providers.dart' as sales;
import '../data/firestore_sales_repository.dart';
import '../domain/quantity_input.dart';
import '../domain/sale.dart';
import '../domain/sale_models.dart';
import 'sales_navigation.dart';
import 'share_receipt_to_customer_sheet.dart';

class InvalidSaleScreen extends StatelessWidget {
  const InvalidSaleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sale Details')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.mutedText,
                ),
                const SizedBox(height: 16),
                Text(
                  'Invalid sale',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This record could not be found. It may have been removed or archived.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.sales),
                  child: const Text('Back to Sales'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SaleDetailsScreen extends ConsumerWidget {
  const SaleDetailsScreen({required this.saleId, super.key});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmedId = saleId.trim();
    if (trimmedId.isEmpty) {
      return const InvalidSaleScreen();
    }

    final active = ref.watch(activeBusinessProvider);
    return active.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Sale Details')),
        body: const _SaleStateMessage(
          title: 'Unable to load business',
          message: 'Something went wrong. Please try again.',
        ),
      ),
      data: (state) => switch (state) {
        ActiveBusinessData(:final business) => _SaleDetailsBody(
          businessId: business.businessId,
          saleId: trimmedId,
          currencySymbol: business.currency.symbol,
          currencyCode: business.currency.code,
        ),
        ActiveBusinessNone() => Scaffold(
          appBar: AppBar(title: const Text('Sale Details')),
          body: const _SaleStateMessage(
            title: 'No active business',
            message: 'Set up or select a business to continue.',
          ),
        ),
        ActiveBusinessFailure(:final message) => Scaffold(
          appBar: AppBar(title: const Text('Sale Details')),
          body: _SaleStateMessage(
            title: 'Unable to load business',
            message: message,
          ),
        ),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    );
  }
}

class _SaleDetailsBody extends ConsumerWidget {
  const _SaleDetailsBody({
    required this.businessId,
    required this.saleId,
    required this.currencySymbol,
    required this.currencyCode,
  });

  final String businessId;
  final String saleId;
  final String currencySymbol;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sales.saleDocumentProvider((businessId, saleId)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Details'),
        actions: <Widget>[
          RecordSyncStatusIcon(
            request: RecordSyncRequest(
              businessId: businessId,
              collection: 'sales',
              recordId: saleId,
            ),
          ),
          IconButton(
            tooltip: 'View Receipt',
            onPressed: () => SalesNavigation.openSaleReceipt(context, saleId),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _SaleLoadError(
          error: error,
          onRetry: () =>
              ref.invalidate(sales.saleDocumentProvider((businessId, saleId))),
          onBack: () => context.go(AppRoutes.sales),
        ),
        data: (sale) {
          if (sale == null) {
            return _SaleStateMessage(
              title: 'Sale not found',
              message:
                  'This record could not be found. It may have been removed or archived.',
              actionLabel: 'Back to Sales',
              onAction: () => context.go(AppRoutes.sales),
            );
          }
          return _SaleDetailsContent(
            sale: sale,
            businessId: businessId,
            currencySymbol: currencySymbol,
            currencyCode: currencyCode,
          );
        },
      ),
    );
  }
}

class _SaleDetailsContent extends ConsumerWidget {
  const _SaleDetailsContent({
    required this.sale,
    required this.businessId,
    required this.currencySymbol,
    required this.currencyCode,
  });

  final Sale sale;
  final String businessId;
  final String currencySymbol;
  final String currencyCode;

  String _money(int minor) => formatCurrency(
    minorToMoney(minor),
    code: currencyCode,
    symbol: currencySymbol,
  );

  Future<void> _requestVoidSale(
    BuildContext context,
    WidgetRef ref,
    bool canVoid,
  ) async {
    if (!canVoid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You do not have permission to void sales. Contact the business owner or manager.',
          ),
        ),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void sale?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final branchId = sale.branchId;
    if (branchId == null || branchId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This legacy sale must be migrated before it can be voided.',
          ),
        ),
      );
      return;
    }

    try {
      final membership = ref
          .read(currentBusinessMembershipProvider)
          .asData
          ?.value;
      final policies =
          ref.read(approvalPoliciesProvider).asData?.value ??
          const ApprovalPolicies();
      final outcome = await ref
          .read(saleVoidServiceProvider)
          .voidOrRequestApproval(
            businessId: businessId,
            branchId: branchId,
            saleId: sale.id,
            receiptNumber: sale.receiptNumber,
            reason: reasonCtrl.text,
            membership: membership,
            policies: policies,
            totalMinor: sale.totalMinor,
            currencySymbol: currencySymbol,
          );
      if (!context.mounted) return;
      if (outcome == SaleVoidOutcome.approvalRequested) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Approval requested. The sale will void after a manager approves.',
            ),
          ),
        );
        context.pushNamed(AppRouteNames.approvals);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sale voided.')));
      }
    } on SaleException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.friendlyMessage)));
      }
    } on TeamException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TeamException.fromObject(e).message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = sale.createdAt == null
        ? 'Date unavailable'
        : DateFormat('EEE, d MMM yyyy · HH:mm').format(sale.createdAt!);
    final active = ref.watch(activeBusinessProvider).asData?.value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sale.receiptNumber,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateLabel,
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _StatusChip(
                        label: _saleStatusLabel(sale.saleStatus),
                        color: sale.isVoided
                            ? Colors.red.shade100
                            : const Color(0xFFD1FADF),
                      ),
                      _StatusChip(
                        label: _paymentStatusLabel(sale.paymentStatus),
                        color: const Color(0xFFEDE9FE),
                      ),
                      _StatusChip(
                        label: sale.paymentMethod.label,
                        color: const Color(0xFFEEF2FF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _InfoRow(label: 'Customer', value: sale.customerName),
                  if (sale.branchNameSnapshot?.isNotEmpty == true)
                    _InfoRow(label: 'Branch', value: sale.branchNameSnapshot!),
                  if (sale.branchCodeSnapshot?.isNotEmpty == true)
                    _InfoRow(
                      label: 'Branch Code',
                      value: sale.branchCodeSnapshot!,
                    ),
                  if (sale.customerPhone != null &&
                      sale.customerPhone!.trim().isNotEmpty)
                    _InfoRow(label: 'Phone', value: sale.customerPhone!),
                  _InfoRow(
                    label: 'Cashier',
                    value: sale.cashierName?.trim().isNotEmpty == true
                        ? sale.cashierName!
                        : '—',
                  ),
                  if (sale.note != null && sale.note!.trim().isNotEmpty)
                    _InfoRow(label: 'Notes', value: sale.note!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Items',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: sale.items
                  .map(
                    (item) => ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                        '${formatSaleQuantityLabel(quantity: item.quantity, unit: item.unit, quantityInput: item.quantityInput)} × ${formatSaleUnitPriceLabel(formattedMoney: _money(item.unitPriceMinor), unitPriceInput: item.unitPriceInput)}',
                      ),
                      trailing: Text(
                        _money(item.lineTotalMinor),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _MoneyRow(
                    label: 'Subtotal',
                    value: _money(sale.subtotalMinor),
                  ),
                  if (sale.discountMinor > 0)
                    _MoneyRow(
                      label: 'Discount',
                      value: '-${_money(sale.discountMinor)}',
                    ),
                  if (sale.taxMinor > 0)
                    _MoneyRow(label: 'Tax', value: _money(sale.taxMinor)),
                  const Divider(height: 20),
                  _MoneyRow(
                    label: 'Total',
                    value: _money(sale.totalMinor),
                    bold: true,
                  ),
                  _MoneyRow(
                    label: 'Amount paid',
                    value: _money(sale.amountPaidMinor),
                  ),
                  if (sale.changeMinor > 0)
                    _MoneyRow(label: 'Change', value: _money(sale.changeMinor)),
                  if (sale.balanceDueMinor > 0)
                    _MoneyRow(
                      label: 'Balance due',
                      value: _money(sale.balanceDueMinor),
                      bold: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => SalesNavigation.openSaleReceipt(context, sale.id),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View Receipt'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: active is! ActiveBusinessData
                ? null
                : () => _downloadPdf(context, active),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: active is! ActiveBusinessData
                ? null
                : () => _openWithPdfReader(context, active),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Open with PDF reader'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: active is! ActiveBusinessData
                ? null
                : () => _sharePdf(context, active),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: active is! ActiveBusinessData
                ? null
                : () {
                    final snapshot = sale.receiptTemplateSnapshot;
                    final template = ReceiptTemplate.fromSnapshot(
                      businessId,
                      snapshot,
                    );
                    showShareReceiptToCustomerSheet(
                      context: context,
                      ref: ref,
                      business: active.business,
                      sale: sale,
                      template: template,
                    );
                  },
            icon: const Icon(Icons.people_outline),
            label: const Text('Share with customer'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: active is! ActiveBusinessData
                ? null
                : () => _printPdf(context, active),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print PDF'),
          ),
          if (!sale.isVoided) ...<Widget>[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final canVoid = ref.watch(
                  hasPermissionProvider(AppPermission.voidSale),
                );
                return TextButton.icon(
                  onPressed: () => _requestVoidSale(context, ref, canVoid),
                  icon: const Icon(Icons.block_outlined),
                  label: Text(canVoid ? 'Void Sale' : 'Void Sale (restricted)'),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(AppRoutes.sales),
            child: const Text('Back to Sales'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildPdf(ActiveBusinessData active) async {
    final template = await ReceiptTemplateRepository().getDefaultTemplate(
      businessId,
      preferredId: active.business.defaultReceiptTemplateId,
    );
    return ReceiptPdfService().buildPdf(
      sale: sale,
      business: active.business,
      template: template,
    );
  }

  Future<void> _downloadPdf(
    BuildContext context,
    ActiveBusinessData active,
  ) async {
    try {
      final bytes = await _buildPdf(active);
      final saved = await ReceiptShareService().downloadPdf(
        bytes: bytes,
        receiptNumber: sale.receiptNumber,
      );
      if (!context.mounted) return;
      final location = saved.savedToDownloads
          ? 'Downloads'
          : 'your SabiBom receipts folder';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Receipt saved to $location.'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => ReceiptShareService().openPdf(saved.file),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The receipt PDF could not be saved. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _openWithPdfReader(
    BuildContext context,
    ActiveBusinessData active,
  ) async {
    try {
      final bytes = await _buildPdf(active);
      final result = await ReceiptShareService().downloadAndOpenPdf(
        bytes: bytes,
        receiptNumber: sale.receiptNumber,
      );
      if (!context.mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isEmpty
                  ? 'No PDF reader found. Install a PDF app and try again.'
                  : result.message,
            ),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => ReceiptShareService().sharePdf(
                bytes: bytes,
                receiptNumber: sale.receiptNumber,
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The receipt PDF could not be opened. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _sharePdf(
    BuildContext context,
    ActiveBusinessData active,
  ) async {
    try {
      final bytes = await _buildPdf(active);
      await ReceiptShareService().sharePdf(
        bytes: bytes,
        receiptNumber: sale.receiptNumber,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The receipt PDF could not be created. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _printPdf(
    BuildContext context,
    ActiveBusinessData active,
  ) async {
    try {
      final bytes = await _buildPdf(active);
      await ReceiptShareService().printPdf(bytes);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The receipt PDF could not be created. Please try again.',
          ),
        ),
      );
    }
  }

  static String _saleStatusLabel(SaleStatus status) => switch (status) {
    SaleStatus.draft => 'Draft',
    SaleStatus.completed => 'Completed',
    SaleStatus.voided => 'Voided',
  };

  static String _paymentStatusLabel(PaymentStatus status) => switch (status) {
    PaymentStatus.paid => 'Paid',
    PaymentStatus.partiallyPaid => 'Partially paid',
    PaymentStatus.unpaid => 'Unpaid',
  };
}

class _SaleLoadError extends StatelessWidget {
  const _SaleLoadError({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final message = _friendlyError(error);
    return _SaleStateMessage(
      title: 'Unable to load sale',
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
      secondaryLabel: 'Back to Sales',
      onSecondary: onBack,
    );
  }

  static String _friendlyError(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          'You do not have permission to access this business information.',
        'unavailable' =>
          'This information is temporarily unavailable. Please try again.',
        'not-found' =>
          'This record could not be found. It may have been removed or archived.',
        _ => 'Something went wrong. Please try again.',
      };
    }
    return 'Something went wrong. Please try again.';
  }
}

class _SaleStateMessage extends StatelessWidget {
  const _SaleStateMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.info_outline,
              size: 48,
              color: AppColors.mutedText,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryLabel != null && onSecondary != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : const Color(0xFF1F2937),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.mutedText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
