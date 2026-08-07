import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/formatting/currency_formatter.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/product_intelligence_report_models.dart';
import '../domain/profit_models.dart';

class ReportPdfService {
  Future<Uint8List> buildProfitLossPdf({
    required String businessName,
    required String currencyCode,
    required String currencySymbol,
    required DateTime start,
    required DateTime end,
    required ProfitPeriodSummary summary,
  }) async {
    final document = pw.Document();
    String money(int amount) => formatCurrency(
      minorToMoney(amount),
      code: currencyCode,
      symbol: currencySymbol,
    );
    final rows = <(String, String)>[
      ('Gross sales', money(summary.grossSalesMinor)),
      ('Sales discounts', '-${money(summary.salesDiscountMinor)}'),
      ('Net sales', money(summary.netSalesMinor)),
      (
        'Cost of goods sold${summary.cogsEstimated ? ' (estimated)' : ''}',
        '-${money(summary.cogsMinor)}',
      ),
      ('Gross profit', money(summary.grossProfitMinor)),
      ('Operating expenses', '-${money(summary.expenseMinor)}'),
      ('Net profit', money(summary.netProfitMinor)),
      ('Stock value', money(summary.stockValueMinor)),
      ('Supplier debt', money(summary.supplierDebtMinor)),
      ('Customer debt', money(summary.customerDebtMinor)),
    ];
    final range =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}'
        ' – ${end.subtract(const Duration(days: 1)).day.toString().padLeft(2, '0')}/${end.subtract(const Duration(days: 1)).month.toString().padLeft(2, '0')}/${end.subtract(const Duration(days: 1)).year}';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) => [
          pw.Text(
            businessName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Profit & Loss Report',
            style: const pw.TextStyle(fontSize: 16),
          ),
          pw.Text(range),
          pw.SizedBox(height: 20),
          if (summary.unavailableReason != null)
            pw.Text(
              summary.unavailableReason!,
              style: const pw.TextStyle(color: PdfColors.red),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Summary', 'Amount'],
              data: rows.map((row) => [row.$1, row.$2]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerRight,
              cellAlignments: {0: pw.Alignment.centerLeft},
            ),
        ],
      ),
    );
    return document.save();
  }

  Future<Uint8List> buildProductProfitPdf({
    required String businessName,
    required String currencyCode,
    required String currencySymbol,
    required DateTime start,
    required DateTime end,
    required ProductProfitReport report,
  }) async {
    final document = pw.Document();
    String money(int amount) => formatCurrency(
      minorToMoney(amount),
      code: currencyCode,
      symbol: currencySymbol,
    );
    final range =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}'
        ' – ${end.subtract(const Duration(days: 1)).day.toString().padLeft(2, '0')}/${end.subtract(const Duration(days: 1)).month.toString().padLeft(2, '0')}/${end.subtract(const Duration(days: 1)).year}';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) => [
          pw.Text(
            businessName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Product Profit Report',
            style: const pw.TextStyle(fontSize: 16),
          ),
          pw.Text(range),
          pw.SizedBox(height: 12),
          pw.Text(
            'Realized: ${money(report.totalRealizedGrossProfitMinor)}  ·  '
            'Potential remaining: ${money(report.totalPotentialProfitRemainingMinor)}  ·  '
            'Projected: ${money(report.totalProjectedGrossProfitMinor)}'
            '${report.anyEstimated ? '  ·  Includes estimated rows' : ''}',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Product',
              'Sold',
              'Realized',
              'Potential',
              'Projected',
            ],
            data: report.rows
                .take(80)
                .map(
                  (row) => [
                    row.name,
                    row.quantitySold.toString(),
                    money(row.realizedGrossProfitMinor),
                    money(row.potentialProfitRemainingMinor),
                    money(row.projectedGrossProfitMinor),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {0: pw.Alignment.centerLeft},
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<Uint8List> buildProductExpiryPdf({
    required String businessName,
    required String currencyCode,
    required String currencySymbol,
    required ProductExpiryReport report,
  }) async {
    final document = pw.Document();
    String money(int amount) => formatCurrency(
      minorToMoney(amount),
      code: currencyCode,
      symbol: currencySymbol,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
        ),
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text(
              businessName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Product Expiry Report',
              style: const pw.TextStyle(fontSize: 16),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Expired qty: ${report.totalExpiredQuantity}  ·  '
              'Expired cost: ${money(report.totalExpiredCostMinor)}  ·  '
              'Expiring qty: ${report.totalExpiringQuantity}  ·  '
              'Unknown qty: ${report.totalUnknownQuantity}',
            ),
            pw.SizedBox(height: 16),
          ];
          for (final section in report.sections) {
            widgets.add(
              pw.Text(
                section.title,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 6));
            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Product',
                  'Qty',
                  'Expiry',
                  'Cost',
                  'Potential loss',
                ],
                data: section.rows
                    .take(40)
                    .map(
                      (row) => [
                        row.productName,
                        row.quantityRemaining.toString(),
                        row.expiryDate?.toIso8601String().substring(0, 10) ??
                            'Unknown',
                        money(row.costValueMinor),
                        money(row.potentialProfitLossMinor),
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignment: pw.Alignment.centerRight,
                cellAlignments: {0: pw.Alignment.centerLeft},
              ),
            );
            widgets.add(pw.SizedBox(height: 14));
          }
          return widgets;
        },
      ),
    );
    return document.save();
  }
}
