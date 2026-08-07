import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

import '../../../business_setup/domain/business.dart';
import '../../../receipts/data/firestore_receipt_template_repository.dart';
import '../../../receipts/services/receipt_pdf_service.dart';
import '../../../receipts/services/receipt_share_service.dart';
import '../../domain/sale.dart';

/// Renders a sale's receipt exactly as the PDF the merchant shares,
/// using the business's current default template so recent Receipt Designer
/// changes immediately reflect in preview and shared PDF output.
final saleReceiptPdfBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, SaleReceiptRequest>((
      ref,
      request,
    ) async {
      final sale = request.sale;
      final business = request.business;
      final template = await ReceiptTemplateRepository().getDefaultTemplate(
        business.businessId,
        preferredId: business.defaultReceiptTemplateId,
      );

      return ReceiptPdfService().buildPdf(
        sale: sale,
        business: business,
        template: template,
      );
    });

class SaleReceiptRequest {
  const SaleReceiptRequest({required this.sale, required this.business});

  final Sale sale;
  final Business business;

  @override
  bool operator ==(Object other) =>
      other is SaleReceiptRequest &&
      other.sale.id == sale.id &&
      other.business.businessId == business.businessId;

  @override
  int get hashCode => Object.hash(sale.id, business.businessId);
}

/// Live preview of the styled receipt for [sale].
class SaleReceiptPreview extends ConsumerWidget {
  const SaleReceiptPreview({
    required this.sale,
    required this.business,
    this.showActions = false,
    super.key,
  });

  final Sale sale;
  final Business business;

  /// Shows download / open / share / print actions when true.
  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(
      saleReceiptPdfBytesProvider(
        SaleReceiptRequest(sale: sale, business: business),
      ),
    );
    return bytes.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('The receipt preview could not be created.'),
        ),
      ),
      data: (pdf) {
        if (!showActions) {
          return PdfPreview(
            build: (format) async => pdf,
            useActions: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            pdfFileName: '${sale.receiptNumber}.pdf',
            loadingWidget: const Center(child: CircularProgressIndicator()),
            previewPageMargin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            scrollViewDecoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          );
        }

        return Column(
          children: <Widget>[
            Expanded(
              child: PdfPreview(
                build: (format) async => pdf,
                useActions: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                pdfFileName: '${sale.receiptNumber}.pdf',
                loadingWidget: const Center(child: CircularProgressIndicator()),
                previewPageMargin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                scrollViewDecoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ReceiptPdfActions(
                  bytes: pdf,
                  receiptNumber: sale.receiptNumber,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReceiptPdfActions extends StatefulWidget {
  const _ReceiptPdfActions({
    required this.bytes,
    required this.receiptNumber,
  });

  final Uint8List bytes;
  final String receiptNumber;

  @override
  State<_ReceiptPdfActions> createState() => _ReceiptPdfActionsState();
}

class _ReceiptPdfActionsState extends State<_ReceiptPdfActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ReceiptShareService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final saved = await service.downloadPdf(
                    bytes: widget.bytes,
                    receiptNumber: widget.receiptNumber,
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
                        onPressed: () => service.openPdf(saved.file),
                      ),
                    ),
                  );
                }),
          icon: const Icon(Icons.download_outlined),
          label: Text(_busy ? 'Working...' : 'Download PDF'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final result = await service.downloadAndOpenPdf(
                    bytes: widget.bytes,
                    receiptNumber: widget.receiptNumber,
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
                          onPressed: () => service.sharePdf(
                            bytes: widget.bytes,
                            receiptNumber: widget.receiptNumber,
                          ),
                        ),
                      ),
                    );
                  }
                }),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open with PDF reader'),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => service.sharePdf(
                          bytes: widget.bytes,
                          receiptNumber: widget.receiptNumber,
                        ),
                      ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => service.printPdf(widget.bytes)),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
