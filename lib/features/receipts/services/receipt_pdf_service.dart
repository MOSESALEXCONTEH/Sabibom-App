import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/network/ipfs_url.dart';
import '../../business_setup/domain/business.dart';
import '../../sales/domain/quantity_input.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/receipt_template.dart';

class ReceiptPdfService {
  ReceiptPdfService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const Map<ReceiptShadingStyle, String> _shadingAssets =
      <ReceiptShadingStyle, String>{
        ReceiptShadingStyle.softWave: 'assets/Shading background/1.png',
        ReceiptShadingStyle.darkMesh: 'assets/Shading background/2.png',
        ReceiptShadingStyle.cornerGlow: 'assets/Shading background/3.png',
        ReceiptShadingStyle.auroraMist: 'assets/Shading background/4.png',
        ReceiptShadingStyle.diagonalSweep: 'assets/Shading background/5.png',
        ReceiptShadingStyle.sunsetBloom: 'assets/Shading background/6.png',
        ReceiptShadingStyle.paperTexture: 'assets/Shading background/7.png',
      };

  Future<Uint8List?> _safeShadingAssetBytes(ReceiptShadingStyle style) async {
    final path = _shadingAssets[style];
    if (path == null) return null;
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _safeShadingNetworkBytes(String url) async {
    try {
      final response = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {
      // Fall through to built-in asset fallback.
    }
    return null;
  }

  Future<Uint8List?> _safeShadingBytes(ReceiptTemplate layout) async {
    final remoteUrl = layout.shadingImageUrl?.trim();
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final fromNetwork = await _safeShadingNetworkBytes(remoteUrl);
      if (fromNetwork != null) return fromNetwork;
    }
    return _safeShadingAssetBytes(layout.shadingStyle);
  }

  Future<Uint8List?> _safeLogoBytes({String? url, String? cid}) async {
    for (final candidate in IpfsUrl.candidates(url: url, cid: cid)) {
      try {
        final response = await _http
            .get(Uri.parse(candidate))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (_) {
        // A receipt should still render when a remote logo is unavailable.
      }
    }
    return null;
  }

  Future<Uint8List> buildPdf({
    required Sale sale,
    required Business business,
    required ReceiptTemplate template,
    Map<String, dynamic>? templateSnapshot,
  }) async {
    // Prefer sale snapshot when present so historical receipts stay frozen.
    final layout = templateSnapshot == null || templateSnapshot.isEmpty
        ? template
        : ReceiptTemplate.fromSnapshot(business.businessId, templateSnapshot);
    final shadingBytes = await _safeShadingBytes(layout);

    final logoBytes = await _safeLogoBytes(
      url: (templateSnapshot?['logoUrl'] as String?) ?? business.logoUrl,
      cid: (templateSnapshot?['logoCid'] as String?) ?? business.logoCid,
    );
    final businessName =
        (templateSnapshot?['businessName'] as String?)?.trim().isNotEmpty ==
            true
        ? templateSnapshot!['businessName'] as String
        : business.name;
    final businessAddress =
        (templateSnapshot?['businessAddress'] as String?) ?? business.address;
    final businessPhone =
        (templateSnapshot?['businessPhone'] as String?) ?? business.phoneNumber;
    final businessTagline =
        (templateSnapshot?['businessTagline'] as String?) ??
        business.businessTagline;

    final ctx = _ReceiptRenderContext(
      sale: sale,
      business: business,
      layout: layout,
      logoBytes: logoBytes,
      primary: _applyAlpha(_color(layout.primaryColor), layout.accentAlpha),
      secondary: _applyAlpha(_color(layout.secondaryColor), layout.accentAlpha),
      text: _color(layout.textColor),
      background: _color(layout.backgroundColor),
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessTagline: businessTagline,
      businessEmail: business.email,
      businessWebsite: business.website,
      shadingBytes: shadingBytes,
    );

    final pageFormat = switch (layout.paperSize) {
      ReceiptPaperSize.thermal58 => const PdfPageFormat(
        58 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 8,
      ),
      ReceiptPaperSize.thermal80 => const PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 10,
      ),
      ReceiptPaperSize.a4 => PdfPageFormat.a4,
      ReceiptPaperSize.digital => PdfPageFormat.a4,
    };

    final theme = switch (layout.templateType) {
      ReceiptTemplateType.boutique => pw.ThemeData.withFont(
        base: pw.Font.times(),
        bold: pw.Font.timesBold(),
        italic: pw.Font.timesItalic(),
      ),
      ReceiptTemplateType.retail => pw.ThemeData.withFont(
        base: pw.Font.courier(),
        bold: pw.Font.courierBold(),
      ),
      _ => null,
    };

    final hasBackground =
        layout.backgroundColor.toUpperCase().replaceAll('#', '') != 'FFFFFF';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          theme: theme,
          buildBackground: hasBackground
              ? (context) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Stack(
                    children: <pw.Widget>[
                      pw.Container(color: ctx.background),
                      _buildShadingOverlay(ctx),
                    ],
                  ),
                )
              : (context) => _buildShadingOverlay(ctx),
        ),
        build: (context) => _buildForType(ctx),
      ),
    );
    return doc.save();
  }

  pw.Widget _buildForType(_ReceiptRenderContext ctx) {
    return switch (ctx.layout.templateType) {
      ReceiptTemplateType.modern => _buildModern(ctx),
      ReceiptTemplateType.classic => _buildClassic(ctx),
      ReceiptTemplateType.minimal => _buildMinimal(ctx),
      ReceiptTemplateType.luxury => _buildLuxury(ctx),
      ReceiptTemplateType.gradient => _buildGradient(ctx),
      ReceiptTemplateType.corporate => _buildCorporate(ctx),
      ReceiptTemplateType.boutique => _buildBoutique(ctx),
      ReceiptTemplateType.bold => _buildBold(ctx),
      ReceiptTemplateType.retail => _buildRetail(ctx),
      ReceiptTemplateType.wave => _buildWave(ctx),
    };
  }

  // ---------------------------------------------------------------------
  // Designs
  // ---------------------------------------------------------------------

  /// Rounded gradient header card, floating receipt pill, soft totals card.
  pw.Widget _buildModern(_ReceiptRenderContext ctx) {
    final gradient = pw.LinearGradient(
      begin: pw.Alignment.topLeft,
      end: pw.Alignment.bottomRight,
      colors: <PdfColor>[ctx.primary, ctx.secondary],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: pw.BoxDecoration(
            gradient: gradient,
            borderRadius: pw.BorderRadius.circular(22),
          ),
          child: _bannerHeader(ctx),
        ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _tint(ctx.primary, 0.1),
              borderRadius: pw.BorderRadius.circular(20),
              border: pw.Border.all(color: ctx.primary, width: 0.8),
            ),
            child: pw.Text(
              ctx.sale.receiptNumber,
              style: pw.TextStyle(
                color: ctx.primary,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        if (ctx.sale.createdAt != null)
          pw.Center(
            child: pw.Text(
              DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
              style: pw.TextStyle(fontSize: 9, color: ctx.text),
            ),
          ),
        _metaLines(ctx, centered: true),
        pw.SizedBox(height: 12),
        _itemsTable(
          ctx,
          headerBackground: _tint(ctx.primary, 0.12),
          headerColor: ctx.primary,
          rounded: true,
          stripeColor: _tint(ctx.secondary, 0.06),
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Container(
                width: 4,
                decoration: pw.BoxDecoration(
                  color: ctx.secondary,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _tint(ctx.primary, 0.06),
                  borderRadius: pw.BorderRadius.circular(14),
                ),
                child: _totalsColumn(ctx),
              ),
            ],
          ),
        ),
        _paymentAndNotes(ctx),
        _dotDivider(ctx),
        _footerBlock(ctx, centered: true),
      ],
    );
  }

  /// Traditional store receipt inside an elegant rounded frame with a
  /// curved title ribbon.
  pw.Widget _buildClassic(_ReceiptRenderContext ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ctx.primary, width: 1.2),
        borderRadius: pw.BorderRadius.circular(16),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: ctx.primary,
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text(
                ctx.headerTitle,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          _logoAndIdentity(ctx, centered: true),
          pw.SizedBox(height: 10),
          _dotDivider(ctx),
          pw.SizedBox(height: 6),
          pw.Text(
            ctx.sale.receiptNumber,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: ctx.text,
            ),
          ),
          if (ctx.sale.createdAt != null)
            pw.Text(
              DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 10, color: ctx.text),
            ),
          _metaLines(ctx, centered: true),
          pw.SizedBox(height: 8),
          _simpleItemLines(ctx),
          pw.SizedBox(height: 6),
          _dotDivider(ctx),
          pw.SizedBox(height: 6),
          _totalsColumn(ctx),
          _paymentAndNotes(ctx),
          if (ctx.layout.showSignature || _showPaidStampImage(ctx))
            _signatureRow(ctx),
          _footerBlock(ctx, centered: true),
        ],
      ),
    );
  }

  /// Airy layout with a soft tinted header pill and rounded total chip.
  pw.Widget _buildMinimal(_ReceiptRenderContext ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: pw.BoxDecoration(
            color: _tint(ctx.primary, 0.05),
            borderRadius: pw.BorderRadius.circular(26),
          ),
          child: pw.Column(
            children: <pw.Widget>[
              if (ctx.layout.showBusinessName)
                pw.Text(
                  ctx.businessName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: ctx.text,
                    letterSpacing: 1.4,
                  ),
                ),
              _contactLines(ctx, centered: true, small: true),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Container(
            width: 5,
            height: 5,
            decoration: pw.BoxDecoration(
              color: ctx.secondary,
              shape: pw.BoxShape.circle,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              ctx.sale.receiptNumber,
              style: pw.TextStyle(fontSize: 9, color: ctx.text),
            ),
            if (ctx.sale.createdAt != null)
              pw.Text(
                DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
                style: pw.TextStyle(fontSize: 9, color: ctx.text),
              ),
          ],
        ),
        _metaLines(ctx, centered: false),
        pw.SizedBox(height: 8),
        pw.Container(height: 0.6, color: ctx.secondary),
        pw.SizedBox(height: 6),
        _simpleItemLines(ctx),
        pw.SizedBox(height: 6),
        pw.Container(height: 0.6, color: ctx.secondary),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: pw.BoxDecoration(
              color: _tint(ctx.secondary, 0.1),
              borderRadius: pw.BorderRadius.circular(24),
            ),
            child: pw.Text(
              'Total ${_money(ctx.sale.totalMinor, ctx.business)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
                color: ctx.text,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: _totalsColumn(ctx, skipTotal: true),
          ),
        ),
        _paymentAndNotes(ctx),
        _footerBlock(ctx, centered: true),
      ],
    );
  }

  /// Dark banner with gold accent, boxed totals — invoice style.
  pw.Widget _buildLuxury(_ReceiptRenderContext ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: ctx.primary,
            border: pw.Border(
              bottom: pw.BorderSide(color: ctx.secondary, width: 4),
            ),
          ),
          child: _bannerHeader(ctx),
        ),
        pw.SizedBox(height: 16),
        _billToRow(ctx),
        pw.SizedBox(height: 14),
        _itemsTable(
          ctx,
          headerBackground: ctx.primary,
          headerColor: PdfColors.white,
          stripeColor: const PdfColor.fromInt(0xFFF8F5EC),
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 220,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: ctx.secondary, width: 1.2),
            ),
            child: _totalsColumn(ctx),
          ),
        ),
        _paymentAndNotes(ctx),
        if (ctx.layout.showSignature || _showPaidStampImage(ctx))
          _signatureRow(ctx),
        _footerBlock(ctx, centered: true),
      ],
    );
  }

  /// Gradient banner and gradient totals band, inspired by premium
  /// invoice templates.
  pw.Widget _buildGradient(_ReceiptRenderContext ctx) {
    final gradient = pw.LinearGradient(
      begin: pw.Alignment.centerLeft,
      end: pw.Alignment.centerRight,
      colors: <PdfColor>[ctx.primary, ctx.secondary],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            gradient: gradient,
            borderRadius: const pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(18),
              bottomRight: pw.Radius.circular(18),
            ),
          ),
          child: _bannerHeader(ctx),
        ),
        pw.SizedBox(height: 16),
        _billToRow(ctx),
        pw.SizedBox(height: 14),
        _itemsTable(
          ctx,
          headerBackground: ctx.primary,
          headerColor: PdfColors.white,
          rounded: true,
          stripeColor: const PdfColor.fromInt(0xFFF6F1FB),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            gradient: gradient,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _money(ctx.sale.totalMinor, ctx.business),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: _totalsColumn(ctx, skipTotal: true),
          ),
        ),
        _paymentAndNotes(ctx),
        if (ctx.layout.showSignature || _showPaidStampImage(ctx))
          _signatureRow(ctx),
        _footerBlock(ctx, centered: true),
      ],
    );
  }

  /// Left accent stripe with structured two-column header.
  pw.Widget _buildCorporate(_ReceiptRenderContext ctx) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(width: 8, height: 760, color: ctx.primary),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Expanded(child: _logoAndIdentity(ctx, centered: false)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: <pw.Widget>[
                      pw.Text(
                        ctx.headerTitle,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: ctx.primary,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        ctx.sale.receiptNumber,
                        style: pw.TextStyle(fontSize: 10, color: ctx.text),
                      ),
                      if (ctx.sale.createdAt != null)
                        pw.Text(
                          DateFormat(
                            'd MMM yyyy HH:mm',
                          ).format(ctx.sale.createdAt!),
                          style: pw.TextStyle(fontSize: 9, color: ctx.text),
                        ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(height: 2, color: ctx.secondary),
              pw.SizedBox(height: 10),
              _billToRow(ctx, showReceiptMeta: false),
              pw.SizedBox(height: 12),
              _itemsTable(
                ctx,
                headerBackground: ctx.primary,
                headerColor: PdfColors.white,
                bordered: true,
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(12),
                  color: PdfColor.fromInt(0x0D000000),
                  child: _totalsColumn(ctx),
                ),
              ),
              _paymentAndNotes(ctx),
              if (ctx.layout.showSignature || _showPaidStampImage(ctx))
                _signatureRow(ctx),
              _footerBlock(ctx, centered: false),
            ],
          ),
        ),
      ],
    );
  }

  /// Elegant serif design framed by an arched double border with a
  /// medallion-style monogram divider.
  pw.Widget _buildBoutique(_ReceiptRenderContext ctx) {
    pw.Widget medallionRule() => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Expanded(child: pw.Container(height: 0.8, color: ctx.secondary)),
        pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 8),
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: ctx.primary, width: 1),
          ),
        ),
        pw.Expanded(child: pw.Container(height: 0.8, color: ctx.secondary)),
      ],
    );
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ctx.secondary, width: 0.8),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(40),
          topRight: pw.Radius.circular(40),
          bottomLeft: pw.Radius.circular(12),
          bottomRight: pw.Radius.circular(12),
        ),
      ),
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(18, 24, 18, 18),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: ctx.primary, width: 1.1),
          borderRadius: const pw.BorderRadius.only(
            topLeft: pw.Radius.circular(36),
            topRight: pw.Radius.circular(36),
            bottomLeft: pw.Radius.circular(10),
            bottomRight: pw.Radius.circular(10),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            _logoAndIdentity(ctx, centered: true),
            if (ctx.headerTitle.isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 6),
              pw.Text(
                ctx.headerTitle,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontStyle: pw.FontStyle.italic,
                  color: ctx.secondary,
                  letterSpacing: 2,
                ),
              ),
            ],
            pw.SizedBox(height: 10),
            medallionRule(),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text(
                  ctx.sale.receiptNumber,
                  style: pw.TextStyle(fontSize: 10, color: ctx.text),
                ),
                if (ctx.sale.createdAt != null)
                  pw.Text(
                    DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
                    style: pw.TextStyle(fontSize: 10, color: ctx.text),
                  ),
              ],
            ),
            _metaLines(ctx, centered: false),
            pw.SizedBox(height: 10),
            _simpleItemLines(ctx),
            pw.SizedBox(height: 8),
            medallionRule(),
            pw.SizedBox(height: 8),
            _totalsColumn(ctx),
            _paymentAndNotes(ctx),
            if (ctx.layout.showSignature || _showPaidStampImage(ctx))
              _signatureRow(ctx),
            _footerBlock(ctx, centered: true, italic: true),
          ],
        ),
      ),
    );
  }

  /// High contrast diagonal-feel header with sweeping curved corners and an
  /// oversized rounded total band.
  pw.Widget _buildBold(_ReceiptRenderContext ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: ctx.primary,
                  borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(24),
                    bottomRight: pw.Radius.circular(48),
                  ),
                ),
                child: _bannerHeader(ctx, showTitle: false),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: ctx.secondary,
                  borderRadius: const pw.BorderRadius.only(
                    topRight: pw.Radius.circular(24),
                    bottomLeft: pw.Radius.circular(48),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(
                      ctx.headerTitle,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      ctx.sale.receiptNumber,
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                      ),
                    ),
                    if (ctx.sale.createdAt != null)
                      pw.Text(
                        DateFormat(
                          'd MMM yyyy HH:mm',
                        ).format(ctx.sale.createdAt!),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        _billToRow(ctx, showReceiptMeta: false),
        pw.SizedBox(height: 12),
        _itemsTable(
          ctx,
          headerBackground: ctx.secondary,
          headerColor: PdfColors.white,
          rounded: true,
          stripeColor: _tint(ctx.primary, 0.05),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: pw.BoxDecoration(
            color: ctx.primary,
            borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(28),
              bottomRight: pw.Radius.circular(28),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _money(ctx.sale.totalMinor, ctx.business),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: _totalsColumn(ctx, skipTotal: true),
          ),
        ),
        _paymentAndNotes(ctx),
        if (ctx.layout.showSignature || _showPaidStampImage(ctx))
          _signatureRow(ctx),
        _footerBlock(ctx, centered: true),
      ],
    );
  }

  /// Compact till-roll style with a scalloped ticket header and dashed
  /// dividers.
  pw.Widget _buildRetail(_ReceiptRenderContext ctx) {
    pw.Widget dashed() => pw.Divider(
      color: ctx.text,
      thickness: 0.6,
      borderStyle: pw.BorderStyle.dashed,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: _tint(ctx.primary, 0.07),
            borderRadius: const pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(22),
              bottomRight: pw.Radius.circular(22),
            ),
          ),
          child: _logoAndIdentity(ctx, centered: true, small: true),
        ),
        pw.SizedBox(height: 6),
        dashed(),
        pw.Text(
          ctx.sale.receiptNumber,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: ctx.text,
          ),
        ),
        if (ctx.sale.createdAt != null)
          pw.Text(
            DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, color: ctx.text),
          ),
        _metaLines(ctx, centered: true, small: true),
        dashed(),
        _simpleItemLines(ctx, small: true),
        dashed(),
        _totalsColumn(ctx, small: true),
        _paymentAndNotes(ctx, small: true),
        dashed(),
        _footerBlock(ctx, centered: true, small: true),
      ],
    );
  }

  /// Layered curved header (two offset waves) with pill totals card and a
  /// curved footer tab.
  pw.Widget _buildWave(_ReceiptRenderContext ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Stack(
          children: <pw.Widget>[
            // Back wave in the accent colour, offset for a layered look.
            pw.Positioned(
              left: 0,
              right: 0,
              top: 10,
              child: pw.Container(
                height: 96,
                decoration: pw.BoxDecoration(
                  color: _tint(ctx.secondary, 0.55),
                  borderRadius: const pw.BorderRadius.only(
                    bottomLeft: pw.Radius.circular(64),
                    bottomRight: pw.Radius.circular(24),
                  ),
                ),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(18, 18, 18, 28),
              decoration: pw.BoxDecoration(
                color: ctx.primary,
                borderRadius: const pw.BorderRadius.only(
                  bottomLeft: pw.Radius.circular(24),
                  bottomRight: pw.Radius.circular(64),
                ),
              ),
              child: pw.Column(
                children: <pw.Widget>[_bannerHeader(ctx, centered: true)],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Center(
          child: pw.Column(
            children: <pw.Widget>[
              pw.Text(
                ctx.sale.receiptNumber,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: ctx.primary,
                ),
              ),
              if (ctx.sale.createdAt != null)
                pw.Text(
                  DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
                  style: pw.TextStyle(fontSize: 9, color: ctx.text),
                ),
            ],
          ),
        ),
        _metaLines(ctx, centered: true),
        pw.SizedBox(height: 12),
        _itemsTable(
          ctx,
          headerBackground: PdfColor.fromInt(0x1A000000),
          headerColor: ctx.primary,
          rounded: true,
        ),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: ctx.secondary,
              borderRadius: pw.BorderRadius.circular(30),
            ),
            child: pw.Text(
              'Total ${_money(ctx.sale.totalMinor, ctx.business)}',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: _totalsColumn(ctx, skipTotal: true),
          ),
        ),
        _paymentAndNotes(ctx),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 26, vertical: 8),
            decoration: pw.BoxDecoration(
              color: _tint(ctx.primary, 0.08),
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(30),
                topRight: pw.Radius.circular(30),
              ),
            ),
            child: pw.Text(
              ctx.layout.footerMessage,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 9, color: ctx.text),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------------

  /// Blends [color] toward white; [strength] 0 is white, 1 is the colour.
  PdfColor _tint(PdfColor color, double strength) {
    return PdfColor(
      1 - (1 - color.red) * strength,
      1 - (1 - color.green) * strength,
      1 - (1 - color.blue) * strength,
    );
  }

  PdfColor _applyAlpha(PdfColor color, double alpha) {
    final a = alpha.clamp(0.2, 1.0);
    return PdfColor(
      1 - (1 - color.red) * a,
      1 - (1 - color.green) * a,
      1 - (1 - color.blue) * a,
    );
  }

  pw.Widget _buildShadingOverlay(_ReceiptRenderContext ctx) {
    if (ctx.layout.shadingStyle != ReceiptShadingStyle.none &&
        ctx.shadingBytes != null) {
      return pw.FullPage(
        ignoreMargins: true,
        child: pw.Opacity(
          opacity: 0.24,
          child: pw.Image(pw.MemoryImage(ctx.shadingBytes!), fit: pw.BoxFit.cover),
        ),
      );
    }

    return switch (ctx.layout.shadingStyle) {
      ReceiptShadingStyle.none => pw.SizedBox(),
      ReceiptShadingStyle.softWave => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Container(
          width: 68,
          margin: const pw.EdgeInsets.symmetric(vertical: 16),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              begin: pw.Alignment.topCenter,
              end: pw.Alignment.bottomCenter,
              colors: <PdfColor>[
                _tint(ctx.primary, 0.23),
                _tint(ctx.secondary, 0.2),
                _tint(ctx.primary, 0.12),
              ],
            ),
            borderRadius: pw.BorderRadius.circular(36),
          ),
        ),
      ),
      ReceiptShadingStyle.cornerGlow => pw.Align(
        alignment: pw.Alignment.topRight,
        child: pw.Container(
          width: 180,
          height: 180,
          decoration: pw.BoxDecoration(
            gradient: pw.RadialGradient(
              center: pw.Alignment.center,
              radius: 1,
              colors: <PdfColor>[ctx.primary, PdfColor(1, 1, 1, 0)],
              stops: const <double>[0, 1],
            ),
          ),
        ),
      ),
      ReceiptShadingStyle.darkMesh => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
              colors: <PdfColor>[
                _tint(ctx.primary, 0.22),
                PdfColor(1, 1, 1, 0),
                _tint(ctx.secondary, 0.2),
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        ),
      ),
      ReceiptShadingStyle.auroraMist => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: <pw.Widget>[
            pw.Align(
              alignment: const pw.Alignment(-1.15, -0.45),
              child: pw.Container(
                width: 240,
                height: 240,
                decoration: pw.BoxDecoration(
                  gradient: pw.RadialGradient(
                    colors: <PdfColor>[ctx.primary, PdfColor(1, 1, 1, 0)],
                    stops: const <double>[0, 1],
                  ),
                ),
              ),
            ),
            pw.Align(
              alignment: const pw.Alignment(1.12, 0.45),
              child: pw.Container(
                width: 280,
                height: 280,
                decoration: pw.BoxDecoration(
                  gradient: pw.RadialGradient(
                    colors: <PdfColor>[ctx.secondary, PdfColor(1, 1, 1, 0)],
                    stops: const <double>[0, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ReceiptShadingStyle.diagonalSweep => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              begin: const pw.Alignment(-1, -1),
              end: const pw.Alignment(1, 1),
              colors: <PdfColor>[
                _tint(ctx.primary, 0.2),
                PdfColor(1, 1, 1, 0),
                _tint(ctx.secondary, 0.18),
              ],
              stops: const <double>[0.08, 0.5, 0.92],
            ),
          ),
        ),
      ),
      ReceiptShadingStyle.sunsetBloom => pw.FullPage(
        ignoreMargins: true,
        child: pw.Align(
          alignment: const pw.Alignment(-0.1, -1),
          child: pw.Container(
            width: 460,
            height: 320,
            decoration: pw.BoxDecoration(
              gradient: pw.RadialGradient(
                colors: <PdfColor>[
                  _tint(ctx.secondary, 0.28),
                  _tint(ctx.primary, 0.14),
                  PdfColor(1, 1, 1, 0),
                ],
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
        ),
      ),
      ReceiptShadingStyle.paperTexture => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: <pw.Widget>[
            pw.Container(color: _tint(ctx.secondary, 0.08)),
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Column(
                children: List<pw.Widget>.generate(
                  28,
                  (index) => pw.Expanded(
                    child: pw.Container(
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: index.isEven
                                ? _tint(ctx.primary, 0.2)
                                : _tint(ctx.secondary, 0.15),
                            width: 0.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    };
  }

  /// Row of small dots used as a decorative divider.
  pw.Widget _dotDivider(_ReceiptRenderContext ctx) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: List<pw.Widget>.generate(
          24,
          (index) => pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            width: 3,
            height: 3,
            decoration: pw.BoxDecoration(
              color: index.isEven ? ctx.primary : ctx.secondary,
              shape: pw.BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _logo(_ReceiptRenderContext ctx, {double size = 64}) {
    final bytes = ctx.logoBytes;
    if (!ctx.layout.logoEnabled || bytes == null) {
      return pw.SizedBox();
    }
    final scaled = switch (ctx.layout.logoSize) {
      ReceiptLogoSize.small => size * 0.7,
      ReceiptLogoSize.medium => size,
      ReceiptLogoSize.large => size * 1.35,
      ReceiptLogoSize.xlarge => size * 1.7,
    };
    final image = pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    final logoBox = switch (ctx.layout.logoShape) {
      ReceiptLogoShape.circle => pw.ClipOval(
        child: pw.SizedBox(width: scaled, height: scaled, child: image),
      ),
      ReceiptLogoShape.rounded => pw.ClipRRect(
        horizontalRadius: 10,
        verticalRadius: 10,
        child: pw.SizedBox(width: scaled, height: scaled, child: image),
      ),
      ReceiptLogoShape.original => pw.SizedBox(
        width: scaled,
        height: scaled,
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
      ),
    };
    return logoBox;
  }

  pw.Alignment _headerAlignment(_ReceiptRenderContext ctx) =>
      switch (ctx.layout.headerAlignment) {
        ReceiptAlignment.left => pw.Alignment.centerLeft,
        ReceiptAlignment.center => pw.Alignment.center,
        ReceiptAlignment.right => pw.Alignment.centerRight,
      };

  /// Logo plus business identity for light headers.
  pw.Widget _logoAndIdentity(
    _ReceiptRenderContext ctx, {
    required bool centered,
    bool small = false,
  }) {
    final align = centered ? pw.TextAlign.center : pw.TextAlign.left;
    final cross = centered
        ? pw.CrossAxisAlignment.center
        : pw.CrossAxisAlignment.start;
    return pw.Column(
      crossAxisAlignment: cross,
      children: <pw.Widget>[
        if (ctx.layout.logoEnabled && ctx.logoBytes != null)
          pw.Align(
            alignment: _headerAlignment(ctx),
            child: _logo(ctx, size: small ? 42 : 64),
          ),
        if (ctx.layout.showBusinessName) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          pw.Text(
            ctx.businessName,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: small
                  ? ctx.layout.businessNameFontSize - 4
                  : ctx.layout.businessNameFontSize,
              fontWeight: pw.FontWeight.bold,
              color: ctx.primary,
            ),
          ),
        ],
        _contactLines(ctx, centered: centered, small: small),
      ],
    );
  }

  pw.Widget _contactLines(
    _ReceiptRenderContext ctx, {
    required bool centered,
    bool small = false,
    PdfColor? color,
  }) {
    final align = centered ? pw.TextAlign.center : pw.TextAlign.left;
    final style = pw.TextStyle(
      fontSize: small
          ? (ctx.layout.bodyFontSize - 2).clamp(7, 16)
          : ctx.layout.bodyFontSize,
      color: color ?? ctx.text,
    );
    final cross = centered
        ? pw.CrossAxisAlignment.center
        : pw.CrossAxisAlignment.start;
    return pw.Column(
      crossAxisAlignment: cross,
      children: <pw.Widget>[
        if (ctx.sale.branchNameSnapshot?.isNotEmpty == true)
          pw.Text(
            'Branch: ${ctx.sale.branchNameSnapshot}',
            textAlign: align,
            style: style,
          ),
        if (ctx.sale.branchCodeSnapshot?.isNotEmpty == true)
          pw.Text(
            'Branch Code: ${ctx.sale.branchCodeSnapshot}',
            textAlign: align,
            style: style,
          ),
        if (ctx.businessTagline?.isNotEmpty == true)
          pw.Text(ctx.businessTagline!, textAlign: align, style: style),
        if (ctx.layout.showBusinessAddress && ctx.businessAddress.isNotEmpty)
          pw.Text(ctx.businessAddress, textAlign: align, style: style),
        if (ctx.layout.showBusinessPhone && ctx.businessPhone.isNotEmpty)
          pw.Text(ctx.businessPhone, textAlign: align, style: style),
        if (ctx.layout.showBusinessEmail &&
            ctx.businessEmail?.isNotEmpty == true)
          pw.Text(ctx.businessEmail!, textAlign: align, style: style),
        if (ctx.layout.showWebsite && ctx.businessWebsite?.isNotEmpty == true)
          pw.Text(ctx.businessWebsite!, textAlign: align, style: style),
      ],
    );
  }

  /// Header block for colored banners (white text).
  pw.Widget _bannerHeader(
    _ReceiptRenderContext ctx, {
    bool showTitle = true,
    bool centered = false,
  }) {
    final identity = pw.Column(
      crossAxisAlignment: centered
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        if (ctx.layout.showBusinessName)
          pw.Text(
            ctx.businessName,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: ctx.layout.businessNameFontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        _contactLines(
          ctx,
          centered: centered,
          small: true,
          color: PdfColors.white,
        ),
      ],
    );
    if (centered) {
      return pw.Column(
        children: <pw.Widget>[
          if (ctx.layout.logoEnabled && ctx.logoBytes != null) ...<pw.Widget>[
            _logo(ctx, size: 52),
            pw.SizedBox(height: 6),
          ],
          identity,
        ],
      );
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        if (ctx.layout.logoEnabled && ctx.logoBytes != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 12),
            child: _logo(ctx, size: 52),
          ),
        pw.Expanded(child: identity),
        if (showTitle)
          pw.Text(
            ctx.headerTitle,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
      ],
    );
  }

  pw.Widget _billToRow(
    _ReceiptRenderContext ctx, {
    bool showReceiptMeta = true,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              if (ctx.layout.showCustomer) ...<pw.Widget>[
                pw.Text(
                  'BILL TO',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: ctx.secondary,
                  ),
                ),
                pw.Text(
                  ctx.sale.customerName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: ctx.text,
                  ),
                ),
              ],
              if (ctx.layout.showCashier &&
                  ctx.sale.cashierName?.isNotEmpty == true)
                pw.Text(
                  'Cashier: ${ctx.sale.cashierName}',
                  style: pw.TextStyle(fontSize: 9, color: ctx.text),
                ),
            ],
          ),
        ),
        if (showReceiptMeta)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                ctx.sale.receiptNumber,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: ctx.primary,
                ),
              ),
              if (ctx.sale.createdAt != null)
                pw.Text(
                  DateFormat('d MMM yyyy HH:mm').format(ctx.sale.createdAt!),
                  style: pw.TextStyle(fontSize: 9, color: ctx.text),
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _metaLines(
    _ReceiptRenderContext ctx, {
    required bool centered,
    bool small = false,
  }) {
    final align = centered ? pw.TextAlign.center : pw.TextAlign.left;
    final style = pw.TextStyle(
      fontSize: small
          ? (ctx.layout.bodyFontSize - 2).clamp(7, 16)
          : ctx.layout.bodyFontSize,
      color: ctx.text,
    );
    return pw.Column(
      crossAxisAlignment: centered
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        if (ctx.layout.showCustomer)
          pw.Text(
            'Customer: ${ctx.sale.customerName}',
            textAlign: align,
            style: style,
          ),
        if (ctx.layout.showCashier && ctx.sale.cashierName?.isNotEmpty == true)
          pw.Text(
            'Cashier: ${ctx.sale.cashierName}',
            textAlign: align,
            style: style,
          ),
      ],
    );
  }

  /// Column-style table with header row, used by A4-like designs.
  pw.Widget _itemsTable(
    _ReceiptRenderContext ctx, {
    required PdfColor headerBackground,
    required PdfColor headerColor,
    PdfColor? stripeColor,
    bool rounded = false,
    bool bordered = false,
  }) {
    final headerStyle = pw.TextStyle(
      color: headerColor,
      fontWeight: pw.FontWeight.bold,
      fontSize: (ctx.layout.bodyFontSize - 1).clamp(8, 16),
    );
    final header = pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: headerBackground,
        borderRadius: rounded ? pw.BorderRadius.circular(8) : null,
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(flex: 5, child: pw.Text('Item', style: headerStyle)),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'Qty',
              textAlign: pw.TextAlign.right,
              style: headerStyle,
            ),
          ),
          if (ctx.layout.showUnitPrice)
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                'Price',
                textAlign: pw.TextAlign.right,
                style: headerStyle,
              ),
            ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'Amount',
              textAlign: pw.TextAlign.right,
              style: headerStyle,
            ),
          ),
        ],
      ),
    );

    final rows = ctx.sale.items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final stripe = stripeColor != null && index.isOdd ? stripeColor : null;
      final name = ctx.layout.showSku && item.sku != null
          ? '${item.name} [${item.sku}]'
          : item.name;
      return pw.Container(
        color: stripe,
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 10),
        decoration: bordered
            ? pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromInt(0x22000000),
                    width: 0.5,
                  ),
                ),
              )
            : null,
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              flex: 5,
              child: pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: ctx.layout.bodyFontSize,
                  color: ctx.text,
                ),
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                formatSaleQuantityLabel(
                  quantity: item.quantity,
                  unit: item.unit,
                  quantityInput: item.quantityInput,
                ),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: ctx.layout.bodyFontSize,
                  color: ctx.text,
                ),
              ),
            ),
            if (ctx.layout.showUnitPrice)
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  formatSaleUnitPriceLabel(
                    formattedMoney: _money(item.unitPriceMinor, ctx.business),
                    unitPriceInput: item.unitPriceInput,
                  ),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: ctx.layout.bodyFontSize,
                    color: ctx.text,
                  ),
                ),
              ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                _money(item.lineTotalMinor, ctx.business),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: ctx.layout.bodyFontSize,
                  color: ctx.text,
                ),
              ),
            ),
          ],
        ),
      );
    });

    return pw.Column(children: <pw.Widget>[header, ...rows]);
  }

  /// Simple one-line-per-item list, used by narrow/simple designs.
  pw.Widget _simpleItemLines(_ReceiptRenderContext ctx, {bool small = false}) {
    final size =
        (small
                ? (ctx.layout.bodyFontSize - 2).clamp(7, 16)
                : ctx.layout.bodyFontSize)
            .toDouble();
    return pw.Column(
      children: ctx.sale.items.map((item) {
        final skuPart = ctx.layout.showSku && item.sku != null
            ? ' [${item.sku}]'
            : '';
        final unitPart = ctx.layout.showUnitPrice
            ? ' @ ${formatSaleUnitPriceLabel(formattedMoney: _money(item.unitPriceMinor, ctx.business), unitPriceInput: item.unitPriceInput)}'
            : '';
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  '${item.name}$skuPart x${formatSaleQuantityLabel(quantity: item.quantity, unit: item.unit, quantityInput: item.quantityInput)}$unitPart',
                  style: pw.TextStyle(fontSize: size, color: ctx.text),
                ),
              ),
              pw.Text(
                _money(item.lineTotalMinor, ctx.business),
                style: pw.TextStyle(fontSize: size, color: ctx.text),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _totalsColumn(
    _ReceiptRenderContext ctx, {
    bool small = false,
    bool skipTotal = false,
  }) {
    return pw.Column(
      children: <pw.Widget>[
        if (ctx.layout.showDiscount && ctx.sale.discountMinor > 0)
          _amountRow(
            'Discount',
            -ctx.sale.discountMinor,
            ctx.business,
            ctx.text,
            baseSize: ctx.layout.bodyFontSize,
            small: small,
          ),
        if (ctx.layout.showTax && ctx.sale.taxMinor > 0)
          _amountRow(
            'Tax',
            ctx.sale.taxMinor,
            ctx.business,
            ctx.text,
            baseSize: ctx.layout.bodyFontSize,
            small: small,
          ),
        if (!skipTotal)
          _amountRow(
            'Total',
            ctx.sale.totalMinor,
            ctx.business,
            ctx.primary,
            bold: true,
            baseSize: ctx.layout.totalFontSize,
            small: small,
          ),
        if (ctx.layout.showPaymentDetails) ...<pw.Widget>[
          _amountRow(
            'Amount paid',
            ctx.sale.amountPaidMinor,
            ctx.business,
            ctx.text,
            baseSize: ctx.layout.bodyFontSize,
            small: small,
          ),
          if (ctx.sale.changeMinor > 0)
            _amountRow(
              'Change',
              ctx.sale.changeMinor,
              ctx.business,
              ctx.text,
              baseSize: ctx.layout.bodyFontSize,
              small: small,
            ),
          if (ctx.sale.balanceDueMinor > 0)
            _amountRow(
              'Balance due',
              ctx.sale.balanceDueMinor,
              ctx.business,
              ctx.text,
              baseSize: ctx.layout.bodyFontSize,
              small: small,
            ),
        ],
      ],
    );
  }

  pw.Widget _paymentAndNotes(_ReceiptRenderContext ctx, {bool small = false}) {
    final size =
        (small
                ? (ctx.layout.bodyFontSize - 2).clamp(7, 16)
                : ctx.layout.bodyFontSize)
            .toDouble();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        if (ctx.layout.showPaymentDetails) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          pw.Text(
            'Payment: ${ctx.sale.paymentMethod.label}',
            style: pw.TextStyle(fontSize: size, color: ctx.text),
          ),
        ],
        if (ctx.layout.showNotes &&
            ctx.sale.note != null &&
            ctx.sale.note!.trim().isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          pw.Text(
            'Notes: ${ctx.sale.note}',
            style: pw.TextStyle(fontSize: size - 1, color: ctx.text),
          ),
        ],
        if (ctx.layout.termsText.trim().isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          pw.Text(
            ctx.layout.termsText,
            style: pw.TextStyle(fontSize: size - 2, color: ctx.text),
          ),
        ],
        if (ctx.layout.returnPolicy.trim().isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          pw.Text(
            ctx.layout.returnPolicy,
            style: pw.TextStyle(fontSize: size - 2, color: ctx.text),
          ),
        ],
      ],
    );
  }

  pw.Widget _signatureRow(_ReceiptRenderContext ctx) {
    final signatureScale = ctx.layout.signatureScale.clamp(0.7, 1.8);
    pw.Widget signatureWidget;
    if (ctx.layout.signatureMode != ReceiptSignatureMode.placeholder &&
        (ctx.layout.signatureImageBase64?.trim().isNotEmpty ?? false)) {
      try {
        final bytes = base64Decode(ctx.layout.signatureImageBase64!.trim());
        signatureWidget = pw.SizedBox(
          width: 170 * signatureScale,
          height: 52 * signatureScale,
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        );
      } catch (_) {
        signatureWidget = pw.SizedBox();
      }
    } else {
      signatureWidget = pw.Container(
        width: 160,
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 0.8)),
        ),
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(
          'Authorized signature',
          style: pw.TextStyle(fontSize: 8, color: ctx.text),
        ),
      );
    }

    pw.Widget? paidStampWidget;
    if (_showPaidStampImage(ctx)) {
      try {
        final bytes = base64Decode(ctx.layout.paidStampImageBase64!.trim());
        paidStampWidget = pw.SizedBox(
          width: 170,
          height: 52,
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        );
      } catch (_) {
        paidStampWidget = pw.SizedBox();
      }
    }

    final children = <pw.Widget>[
      pw.Expanded(child: pw.Align(alignment: pw.Alignment.centerLeft, child: signatureWidget)),
    ];
    if (paidStampWidget != null) {
      children.add(pw.SizedBox(width: 16));
      children.add(pw.Align(alignment: pw.Alignment.centerRight, child: paidStampWidget));
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  bool _showPaidStampImage(_ReceiptRenderContext ctx) {
    final shouldShow = switch (ctx.layout.paidStampMode) {
      ReceiptPaidStampMode.hidden => false,
      ReceiptPaidStampMode.paidOnly =>
        ctx.sale.paymentStatus == PaymentStatus.paid,
      ReceiptPaidStampMode.unpaidOnly =>
        ctx.sale.paymentStatus != PaymentStatus.paid,
      ReceiptPaidStampMode.always => true,
    };
    return shouldShow &&
        (ctx.layout.paidStampImageBase64?.trim().isNotEmpty ?? false);
  }

  pw.Widget _paidStamp(_ReceiptRenderContext ctx) {
    final show = switch (ctx.layout.paidStampMode) {
      ReceiptPaidStampMode.hidden => false,
      ReceiptPaidStampMode.paidOnly =>
        ctx.sale.paymentStatus == PaymentStatus.paid,
      ReceiptPaidStampMode.unpaidOnly =>
        ctx.sale.paymentStatus != PaymentStatus.paid,
      ReceiptPaidStampMode.always => true,
    };
    if (!show) return pw.SizedBox();
    if (_showPaidStampImage(ctx)) return pw.SizedBox();
    final text = ctx.sale.paymentStatus == PaymentStatus.paid
        ? ctx.layout.paidStampText
        : ctx.layout.unpaidStampText;
    if (text.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: ctx.layout.totalFontSize,
          color: _tint(ctx.text, 0.55),
        ),
      ),
    );
  }

  pw.Widget _footerBlock(
    _ReceiptRenderContext ctx, {
    required bool centered,
    bool small = false,
    bool italic = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(
        crossAxisAlignment: centered
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            ctx.layout.footerMessage,
            textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: small
                  ? (ctx.layout.bodyFontSize - 2).clamp(7, 16)
                  : ctx.layout.bodyFontSize,
              color: ctx.text,
              fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
            ),
          ),
          _paidStamp(ctx),
        ],
      ),
    );
  }

  pw.Widget _amountRow(
    String label,
    int minor,
    Business business,
    PdfColor color, {
    required double baseSize,
    bool bold = false,
    bool small = false,
  }) {
    final normal = baseSize.clamp(8, 24).toDouble();
    final boldSize = (baseSize + 1).clamp(9, 26).toDouble();
    final compactNormal = (baseSize - 2).clamp(7, 22).toDouble();
    final compactBold = (baseSize - 1).clamp(8, 24).toDouble();
    final size = small
        ? (bold ? compactBold : compactNormal)
        : (bold ? boldSize : normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: size,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color,
              ),
            ),
          ),
          pw.Text(
            _money(minor, business),
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _money(int minor, Business business) {
    return NumberFormat.currency(
      locale: 'en_GB',
      symbol: '${business.currency.symbol} ',
      decimalDigits: 2,
    ).format(minorToMoney(minor));
  }

  PdfColor _color(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x5B3DF5;
    if (cleaned.length == 6) {
      return PdfColor.fromInt(0xFF000000 | value);
    }
    return PdfColor.fromInt(value);
  }
}

class _ReceiptRenderContext {
  const _ReceiptRenderContext({
    required this.sale,
    required this.business,
    required this.layout,
    required this.logoBytes,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.background,
    required this.businessName,
    required this.businessAddress,
    required this.businessPhone,
    required this.businessTagline,
    required this.businessEmail,
    required this.businessWebsite,
    required this.shadingBytes,
  });

  final Sale sale;
  final Business business;
  final ReceiptTemplate layout;
  final Uint8List? logoBytes;
  final PdfColor primary;
  final PdfColor secondary;
  final PdfColor text;
  final PdfColor background;
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String? businessTagline;
  final String? businessEmail;
  final String? businessWebsite;
  final Uint8List? shadingBytes;

  String get headerTitle => layout.customHeader.trim().isEmpty
      ? 'RECEIPT'
      : layout.customHeader.trim().toUpperCase();
}
