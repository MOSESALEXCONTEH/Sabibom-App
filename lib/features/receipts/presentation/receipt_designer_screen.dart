import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../data/firestore_receipt_template_repository.dart';
import '../data/firestore_shading_background_repository.dart';
import '../domain/receipt_contrast.dart';
import '../domain/receipt_shading_background.dart';
import '../domain/receipt_template.dart';

final receiptTemplateRepositoryProvider = Provider(
  (ref) => ReceiptTemplateRepository(),
);

final shadingBackgroundRepositoryProvider = Provider(
  (ref) => ShadingBackgroundRepository(),
);

class _SignatureStroke {
  const _SignatureStroke(this.points);

  final List<Offset> points;
}

class ReceiptDesignerScreen extends ConsumerStatefulWidget {
  const ReceiptDesignerScreen({super.key});

  @override
  ConsumerState<ReceiptDesignerScreen> createState() =>
      _ReceiptDesignerScreenState();
}

class _ReceiptDesignerScreenState extends ConsumerState<ReceiptDesignerScreen> {
  ReceiptTemplate? _draft;
  var _dirty = false;
  var _saving = false;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up or select a business to continue.')),
      );
    }
    final business = active.business;
    final templatesAsync = ref.watch(_templatesProvider(business.businessId));
    final shadingBackgroundsAsync = ref.watch(_shadingBackgroundsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved receipt design changes.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Receipt Designer'),
          actions: <Widget>[
            TextButton(
              onPressed: _saving || _draft == null
                  ? null
                  : () => _save(business.businessId, setDefault: true),
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
        body: templatesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load templates.')),
          data: (templates) {
            _draft ??= templates.firstWhere(
              (item) => item.isDefault,
              orElse: () => templates.first,
            );
            final draft = _draft!;
            final poorContrast = ReceiptContrast.isPoorContrast(
              draft.textColor,
              draft.backgroundColor,
            );

            final preview = _Preview(
              draft: draft,
              businessName: business.name,
              businessAddress: business.address,
              businessPhone: business.phoneNumber,
              logoUrl: business.logoUrl,
              logoCid: business.logoCid,
              currencySymbol: business.currency.symbol,
              poorContrast: poorContrast,
            );
            final controls = _Controls(
              draft: draft,
              templates: templates,
              shadingBackgrounds:
                  shadingBackgroundsAsync.asData?.value ??
                  const <ReceiptShadingBackground>[],
              brandPrimary: business.brandPrimaryColor,
              brandSecondary: business.brandSecondaryColor,
              brandText: business.receiptTextColor,
              onChanged: (next) => setState(() {
                _draft = next;
                _dirty = true;
              }),
              onResetBranding: () => setState(() {
                _draft = draft.copyWith(
                  primaryColor: business.brandPrimaryColor,
                  secondaryColor: business.brandSecondaryColor,
                  textColor: business.receiptTextColor,
                  backgroundColor: '#FFFFFF',
                );
                _dirty = true;
              }),
            );

            return Column(
              children: <Widget>[
                Expanded(
                  child: isWide
                      ? Row(
                          children: <Widget>[
                            Expanded(child: controls),
                            const VerticalDivider(width: 1),
                            Expanded(child: preview),
                          ],
                        )
                      : _MobileCustomizerLayout(
                          draft: draft,
                          templates: templates,
                          preview: preview,
                          controls: controls,
                        ),
                ),
                const SizedBox.shrink(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _save(
    String businessId, {
    bool setDefault = false,
    bool forceNew = false,
  }) async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final saved = draft.copyWith(
        isDefault: setDefault || (!forceNew && draft.isDefault),
        name: forceNew && !draft.name.toLowerCase().contains('copy')
            ? '${draft.name} copy'
            : draft.name,
      );
      final id = await ref
          .read(receiptTemplateRepositoryProvider)
          .saveTemplate(saved, forceNew: forceNew);
      ref.invalidate(_templatesProvider(businessId));
      setState(() {
        _draft = saved.copyWith(id: id);
        _dirty = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt template saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this template. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

}

final _templatesProvider = StreamProvider.family<List<ReceiptTemplate>, String>(
  (ref, businessId) {
    return ref
        .watch(receiptTemplateRepositoryProvider)
        .watchTemplates(businessId);
  },
);

final _shadingBackgroundsProvider = StreamProvider<List<ReceiptShadingBackground>>(
  (ref) => ref.watch(shadingBackgroundRepositoryProvider).watchBackgrounds(),
);

Color _parseColor(String hex, [Color fallback = AppColors.primary]) {
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

String? _shadingAssetPath(ReceiptShadingStyle style) => switch (style) {
  ReceiptShadingStyle.none => null,
  ReceiptShadingStyle.softWave => 'assets/Shading background/1.png',
  ReceiptShadingStyle.darkMesh => 'assets/Shading background/2.png',
  ReceiptShadingStyle.cornerGlow => 'assets/Shading background/3.png',
  ReceiptShadingStyle.auroraMist => 'assets/Shading background/4.png',
  ReceiptShadingStyle.diagonalSweep => 'assets/Shading background/5.png',
  ReceiptShadingStyle.sunsetBloom => 'assets/Shading background/6.png',
  ReceiptShadingStyle.paperTexture => 'assets/Shading background/7.png',
};

// ---------------------------------------------------------------------------
// Live preview — mimics each of the 10 PDF designs.
// ---------------------------------------------------------------------------

class _Preview extends StatelessWidget {
  const _Preview({
    required this.draft,
    required this.businessName,
    required this.businessAddress,
    required this.businessPhone,
    required this.logoUrl,
    required this.logoCid,
    required this.currencySymbol,
    required this.poorContrast,
  });

  final ReceiptTemplate draft;
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String? logoUrl;
  final String? logoCid;
  final String currencySymbol;
  final bool poorContrast;

  @override
  Widget build(BuildContext context) {
    final isThermal =
        draft.paperSize == ReceiptPaperSize.thermal58 ||
        draft.paperSize == ReceiptPaperSize.thermal80;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isThermal ? 260 : 440),
            child: _ReceiptMockup(
              draft: draft,
              businessName: businessName,
              businessAddress: businessAddress,
              businessPhone: businessPhone,
              logoUrl: logoUrl,
              logoCid: logoCid,
              currencySymbol: currencySymbol,
              monochrome: isThermal,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptMockup extends StatelessWidget {
  const _ReceiptMockup({
    required this.draft,
    required this.businessName,
    required this.businessAddress,
    required this.businessPhone,
    required this.logoUrl,
    required this.logoCid,
    required this.currencySymbol,
    required this.monochrome,
  });

  final ReceiptTemplate draft;
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String? logoUrl;
  final String? logoCid;
  final String currencySymbol;
  final bool monochrome;

  Color get _primary => monochrome
      ? Colors.black87
      : _parseColor(draft.primaryColor).withValues(alpha: draft.accentAlpha);
  Color get _secondary => monochrome
      ? Colors.black54
      : _parseColor(draft.secondaryColor).withValues(alpha: draft.accentAlpha);
  Color get _text => monochrome ? Colors.black87 : _parseColor(draft.textColor);
  Color get _background =>
      monochrome ? Colors.white : _parseColor(draft.backgroundColor);

  String get _headerTitle => draft.customHeader.trim().isEmpty
      ? 'RECEIPT'
      : draft.customHeader.trim().toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _shadingOverlay()),
            switch (draft.templateType) {
              ReceiptTemplateType.luxury => _banner(gradient: false),
              ReceiptTemplateType.gradient => _banner(gradient: true),
              ReceiptTemplateType.bold => _boldBlocks(),
              ReceiptTemplateType.wave => _wave(),
              ReceiptTemplateType.corporate => _corporate(),
              ReceiptTemplateType.modern => _modern(),
              ReceiptTemplateType.classic => _classicFrame(),
              ReceiptTemplateType.boutique => _boutiqueFrame(),
              _ => _centered(),
            },
          ],
        ),
      ),
    );
  }

  Widget _shadingOverlay() {
    final shadingImageUrl = draft.shadingImageUrl?.trim();
    if (shadingImageUrl != null && shadingImageUrl.isNotEmpty) {
      return Opacity(
        opacity: 0.24,
        child: Image.network(
          shadingImageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }

    final imageAsset = _shadingAssetPath(draft.shadingStyle);
    if (imageAsset != null) {
      return Opacity(
        opacity: 0.24,
        child: Image.asset(
          imageAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    switch (draft.shadingStyle) {
      case ReceiptShadingStyle.none:
        return const SizedBox.shrink();
      case ReceiptShadingStyle.softWave:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 80,
            margin: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  _tint(_primary, 0.25),
                  _tint(_secondary, 0.2),
                  _tint(_primary, 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        );
      case ReceiptShadingStyle.darkMesh:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                _primary.withValues(alpha: 0.2),
                Colors.transparent,
                _secondary.withValues(alpha: 0.18),
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        );
      case ReceiptShadingStyle.cornerGlow:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, -1),
              radius: 1.1,
              colors: <Color>[_tint(_primary, 0.16), Colors.transparent],
            ),
          ),
        );
      case ReceiptShadingStyle.auroraMist:
        return Stack(
          children: <Widget>[
            Align(
              alignment: const Alignment(-1.1, -0.5),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[
                      _primary.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(1.1, 0.4),
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[
                      _secondary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      case ReceiptShadingStyle.diagonalSweep:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-1, -1),
              end: const Alignment(1, 1),
              stops: const <double>[0.08, 0.5, 0.92],
              colors: <Color>[
                _primary.withValues(alpha: 0.18),
                Colors.transparent,
                _secondary.withValues(alpha: 0.15),
              ],
            ),
          ),
        );
      case ReceiptShadingStyle.sunsetBloom:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.15, -1.05),
              radius: 1.35,
              colors: <Color>[
                _secondary.withValues(alpha: 0.24),
                _primary.withValues(alpha: 0.11),
                Colors.transparent,
              ],
              stops: const <double>[0, 0.45, 1],
            ),
          ),
        );
      case ReceiptShadingStyle.paperTexture:
        return CustomPaint(
          painter: _PaperTexturePainter(
            primary: _primary.withValues(alpha: 0.08),
            secondary: _secondary.withValues(alpha: 0.07),
          ),
        );
    }
  }

  // -- design variants --------------------------------------------------

  Color _tint(Color color, double strength) =>
      Color.lerp(Colors.white, color, strength) ?? color;

  /// Rounded gradient header card with a bordered receipt pill.
  Widget _modern() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[_primary, _secondary],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: <Widget>[
                if (draft.logoEnabled) _logo(),
                if (draft.showBusinessName)
                  Text(
                    businessName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: draft.businessNameFontSize,
                    ),
                  ),
                _contactPreview(Colors.white70, small: true, centered: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: _tint(_primary, 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primary, width: 1),
            ),
            child: Text(
              'SB-SAMPLE-0001',
              style: TextStyle(
                color: _primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _tableHeader(),
          _sampleItems(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _tint(_primary, 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _totalLine(),
            ),
          ),
          const SizedBox(height: 12),
          _footer(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Rounded border frame with a title pill and dotted dividers.
  Widget _classicFrame() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: _primary, width: 1.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _headerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (draft.logoEnabled) _logo(),
            if (draft.showBusinessName) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                businessName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _primary,
                  fontSize: draft.businessNameFontSize,
                ),
              ),
            ],
            _contactPreview(_text),
            _dottedDivider(),
            Text('SB-SAMPLE-0001', style: TextStyle(color: _text)),
            const SizedBox(height: 6),
            _sampleItems(),
            _dottedDivider(),
            _totalLine(),
            const SizedBox(height: 10),
            _footer(),
          ],
        ),
      ),
    );
  }

  /// Arched double frame with medallion dividers (serif boutique look).
  Widget _boutiqueFrame() {
    Widget medallionRule() => Row(
      children: <Widget>[
        Expanded(child: Container(height: 1, color: _secondary)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _primary, width: 1),
          ),
        ),
        Expanded(child: Container(height: 1, color: _secondary)),
      ],
    );
    const arch = BorderRadius.only(
      topLeft: Radius.circular(34),
      topRight: Radius.circular(34),
      bottomLeft: Radius.circular(10),
      bottomRight: Radius.circular(10),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: _secondary, width: 1),
          borderRadius: arch,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
          decoration: BoxDecoration(
            border: Border.all(color: _primary, width: 1.2),
            borderRadius: arch,
          ),
          child: Column(
            children: <Widget>[
              if (draft.logoEnabled) _logo(),
              if (draft.showBusinessName) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  businessName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _primary,
                    letterSpacing: 1.6,
                    fontSize: draft.businessNameFontSize,
                  ),
                ),
              ],
              if (_headerTitle.isNotEmpty)
                Text(
                  _headerTitle,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: _secondary,
                    letterSpacing: 2,
                  ),
                ),
              _contactPreview(_text, centered: true),
              const SizedBox(height: 8),
              medallionRule(),
              const SizedBox(height: 6),
              Text('SB-SAMPLE-0001', style: TextStyle(color: _text)),
              const SizedBox(height: 6),
              _sampleItems(),
              const SizedBox(height: 6),
              medallionRule(),
              const SizedBox(height: 8),
              _totalLine(),
              const SizedBox(height: 10),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dottedDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(
          18,
          (index) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: index.isEven ? _primary : _secondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _centered() {
    final isRetail = draft.templateType == ReceiptTemplateType.retail;
    final header = Column(
      children: <Widget>[
        if (draft.logoEnabled) Align(alignment: _logoAlignment, child: _logo()),
        if (draft.showBusinessName) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            businessName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: _primary,
              fontSize: draft.businessNameFontSize,
            ),
          ),
        ],
        _contactPreview(_text),
      ],
    );
    return Column(
      children: <Widget>[
        if (isRetail)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: _tint(_primary, 0.07),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
            ),
            child: header,
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              if (!isRetail) header,
              isRetail
                  ? _dashedDivider()
                  : Divider(height: 24, color: _secondary),
              Text('SB-SAMPLE-0001', style: TextStyle(color: _text)),
              const SizedBox(height: 8),
              _sampleItems(),
              isRetail
                  ? _dashedDivider()
                  : Divider(height: 24, color: _secondary),
              _totalLine(),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _banner({required bool gradient}) {
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: gradient ? null : _primary,
            gradient: gradient
                ? LinearGradient(colors: <Color>[_primary, _secondary])
                : null,
            border: gradient
                ? null
                : Border(bottom: BorderSide(color: _secondary, width: 4)),
            borderRadius: gradient
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  )
                : null,
          ),
          child: Row(
            children: <Widget>[
              if (draft.logoEnabled) ...<Widget>[
                _logo(),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (draft.showBusinessName)
                      Text(
                        businessName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: draft.businessNameFontSize.toDouble(),
                        ),
                      ),
                    _contactPreview(Colors.white70, small: true),
                  ],
                ),
              ),
              Text(
                _headerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              _tableHeader(),
              _sampleItems(),
              const SizedBox(height: 10),
              if (gradient)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[_primary, _secondary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$currencySymbol 75.00',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: _secondary, width: 1.2),
                    ),
                    child: _totalLine(),
                  ),
                ),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boldBlocks() {
    return Column(
      children: <Widget>[
        // IntrinsicHeight keeps the stretch Row bounded inside the scroll view.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomRight: Radius.circular(36),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (draft.logoEnabled) _logo(),
                      if (draft.showBusinessName)
                        Text(
                          businessName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      _contactPreview(Colors.white70, small: true),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: _secondary,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(36),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        _headerTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const Text(
                        'SB-SAMPLE-0001',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              _tableHeader(),
              _sampleItems(),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '$currencySymbol 75.00',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wave() {
    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: 10,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: _tint(_secondary, 0.55),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(56),
                    bottomRight: Radius.circular(20),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(56),
                ),
              ),
              child: Column(
                children: <Widget>[
                  if (draft.logoEnabled) _logo(),
                  if (draft.showBusinessName)
                    Text(
                      businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  _contactPreview(Colors.white70, small: true, centered: true),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Text(
                'SB-SAMPLE-0001',
                style: TextStyle(color: _primary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _sampleItems(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _secondary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'Total $currencySymbol 75.00',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _corporate() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(width: 8, color: _primary),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (draft.logoEnabled) ...<Widget>[
                        _logo(),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (draft.showBusinessName)
                              Text(
                                businessName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _primary,
                                ),
                              ),
                            _contactPreview(_text, small: true),
                          ],
                        ),
                      ),
                      Text(
                        _headerTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(height: 2, color: _secondary),
                  const SizedBox(height: 8),
                  _tableHeader(),
                  _sampleItems(),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.black.withValues(alpha: 0.05),
                      child: _totalLine(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(child: _footer()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- shared preview pieces --------------------------------------------

  Alignment get _logoAlignment => switch (draft.headerAlignment) {
    ReceiptAlignment.left => Alignment.centerLeft,
    ReceiptAlignment.right => Alignment.centerRight,
    ReceiptAlignment.center => Alignment.center,
  };

  Widget _logo() {
    final radius = switch (draft.logoSize) {
      ReceiptLogoSize.small => 16.0,
      ReceiptLogoSize.medium => 22.0,
      ReceiptLogoSize.large => 30.0,
      ReceiptLogoSize.xlarge => 40.0,
    };
    final borderRadius = switch (draft.logoShape) {
      ReceiptLogoShape.circle => BorderRadius.circular(999),
      ReceiptLogoShape.rounded => BorderRadius.circular(10),
      ReceiptLogoShape.original => BorderRadius.circular(4),
    };
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.25),
      child: Icon(Icons.storefront, color: _primary, size: radius),
    );
    final hasLogo =
        (logoUrl != null && logoUrl!.trim().isNotEmpty) ||
        (logoCid != null && logoCid!.trim().isNotEmpty);
    if (!hasLogo) return placeholder;
    return AppNetworkImage(
      url: logoUrl ?? '',
      cid: logoCid,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.contain,
      borderRadius: borderRadius,
      fallbackIcon: Icons.storefront,
    );
  }

  Widget _contactPreview(
    Color color, {
    bool small = false,
    bool centered = false,
  }) {
    final style = TextStyle(
      color: color,
      fontSize: small ? draft.bodyFontSize - 2 : draft.bodyFontSize,
    );
    final children = <Widget>[
      if (draft.showBusinessAddress && businessAddress.isNotEmpty)
        Text(businessAddress, style: style, textAlign: TextAlign.center),
      if (draft.showBusinessPhone && businessPhone.isNotEmpty)
        Text(businessPhone, style: style),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: draft.templateType == ReceiptTemplateType.bold
            ? _secondary
            : _primary,
        borderRadius:
            draft.templateType == ReceiptTemplateType.gradient ||
                draft.templateType == ReceiptTemplateType.wave
            ? BorderRadius.circular(6)
            : null,
      ),
      child: const Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              'Item',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Qty',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Amount',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleItems() {
    final rows = <(String, String, String)>[
      ('Sample item', '1', '$currencySymbol 25.00'),
      ('Another item', '2', '$currencySymbol 50.00'),
    ];
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: _text,
                        fontSize: draft.bodyFontSize,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _text,
                        fontSize: draft.bodyFontSize,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _text,
                        fontSize: draft.bodyFontSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _totalLine() {
    return Text(
      'Total  $currencySymbol 75.00',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: _primary,
        fontSize: draft.totalFontSize,
      ),
    );
  }

  Widget _footer() {
    String? statusText() {
      return switch (draft.paidStampMode) {
        ReceiptPaidStampMode.hidden => null,
        ReceiptPaidStampMode.paidOnly => draft.paidStampText,
        ReceiptPaidStampMode.unpaidOnly => draft.unpaidStampText,
        ReceiptPaidStampMode.always => draft.unpaidStampText,
      };
    }

    final paidText = statusText();
    return Column(
      children: <Widget>[
        Text(
          draft.footerMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _text,
            fontSize: draft.bodyFontSize,
            fontStyle: draft.templateType == ReceiptTemplateType.boutique
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        ),
        if (draft.showSignature) ...<Widget>[
          const SizedBox(height: 10),
          if (draft.signatureMode != ReceiptSignatureMode.placeholder &&
              draft.signatureImageBase64 != null &&
              draft.signatureImageBase64!.isNotEmpty)
            Container(
              width: 220 * draft.signatureScale.clamp(0.7, 1.8),
              height: 82 * draft.signatureScale.clamp(0.7, 1.8),
              alignment: Alignment.center,
              child: Image.memory(
                base64Decode(draft.signatureImageBase64!),
                fit: BoxFit.contain,
              ),
            )
          else
            Container(
              width: 160,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Add signature here',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
        if (paidText != null && paidText.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            paidText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text.withValues(alpha: 0.55),
              fontSize: draft.totalFontSize,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dashedDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = (constraints.maxWidth / 8).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(
              count,
              (_) => Container(width: 4, height: 1, color: _text),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.draft,
    required this.templates,
    required this.shadingBackgrounds,
    required this.brandPrimary,
    required this.brandSecondary,
    required this.brandText,
    required this.onChanged,
    required this.onResetBranding,
  });

  final ReceiptTemplate draft;
  final List<ReceiptTemplate> templates;
  final List<ReceiptShadingBackground> shadingBackgrounds;
  final String brandPrimary;
  final String brandSecondary;
  final String brandText;
  final ValueChanged<ReceiptTemplate> onChanged;
  final VoidCallback onResetBranding;

  @override
  Widget build(BuildContext context) {
    return _ControlsBody(
      draft: draft,
      templates: templates,
      shadingBackgrounds: shadingBackgrounds,
      brandPrimary: brandPrimary,
      brandSecondary: brandSecondary,
      brandText: brandText,
      onChanged: onChanged,
      onResetBranding: onResetBranding,
    );
  }
}

class _MobileCustomizerLayout extends StatelessWidget {
  const _MobileCustomizerLayout({
    required this.draft,
    required this.templates,
    required this.preview,
    required this.controls,
  });

  final ReceiptTemplate draft;
  final List<ReceiptTemplate> templates;
  final Widget preview;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(child: preview),
        const Divider(height: 1),
        SizedBox(height: 300, child: controls),
      ],
    );
  }
}

enum _CustomizeTool {
  templates,
  color,
  logo,
  fontSize,
  shading,
  signature,
  paidStamp,
}

class _ControlsBody extends StatefulWidget {
  const _ControlsBody({
    required this.draft,
    required this.templates,
    required this.shadingBackgrounds,
    required this.brandPrimary,
    required this.brandSecondary,
    required this.brandText,
    required this.onChanged,
    required this.onResetBranding,
  });

  final ReceiptTemplate draft;
  final List<ReceiptTemplate> templates;
  final List<ReceiptShadingBackground> shadingBackgrounds;
  final String brandPrimary;
  final String brandSecondary;
  final String brandText;
  final ValueChanged<ReceiptTemplate> onChanged;
  final VoidCallback onResetBranding;

  @override
  State<_ControlsBody> createState() => _ControlsBodyState();
}

class _ControlsBodyState extends State<_ControlsBody> {
  var _tool = _CustomizeTool.templates;
  static const _toolMeta = <(_CustomizeTool, IconData, String)>[
    (_CustomizeTool.templates, Icons.dashboard_customize_outlined, 'Templates'),
    (_CustomizeTool.color, Icons.invert_colors_outlined, 'Color'),
    (_CustomizeTool.logo, Icons.add_business_outlined, 'Logo'),
    (_CustomizeTool.fontSize, Icons.text_fields, 'Font Size'),
    (_CustomizeTool.shading, Icons.texture_outlined, 'Shading'),
    (_CustomizeTool.signature, Icons.draw_outlined, 'Signature'),
    (_CustomizeTool.paidStamp, Icons.approval_outlined, 'Paid Stamp'),
  ];

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final sectionTitle = switch (_tool) {
      _CustomizeTool.templates => 'Design style',
      _CustomizeTool.color => 'Brand colors',
      _CustomizeTool.logo => 'Logo & layout',
      _CustomizeTool.fontSize => 'Typography',
      _CustomizeTool.shading => 'Background mood',
      _CustomizeTool.signature => 'Signature',
      _CustomizeTool.paidStamp => 'Payment stamp',
    };
    final sectionSubtitle = switch (_tool) {
      _CustomizeTool.templates => 'Choose the overall feel of the receipt.',
      _CustomizeTool.color => 'Fine-tune the colors to match your business.',
      _CustomizeTool.logo => 'Control how the store identity appears.',
      _CustomizeTool.fontSize => 'Make the receipt easier to read on-screen and in print.',
      _CustomizeTool.shading => 'Add depth without cluttering the layout.',
      _CustomizeTool.signature => 'Capture a signature that feels natural on mobile.',
      _CustomizeTool.paidStamp => 'Adjust how payment status is shown.',
    };
    final sectionBody = switch (_tool) {
      _CustomizeTool.templates => _templatesSection(context, draft),
      _CustomizeTool.color => _colorSection(draft),
      _CustomizeTool.logo => _logoSection(draft),
      _CustomizeTool.fontSize => _fontSection(draft),
      _CustomizeTool.shading => _shadingSection(draft),
      _CustomizeTool.signature => _signatureSection(draft),
      _CustomizeTool.paidStamp => _paidStampSection(draft),
    };

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + bottomInset),
            children: <Widget>[
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        sectionTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sectionSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...sectionBody,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: _toolPicker(context),
        ),
      ],
    );
  }

  Widget _toolPicker(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _toolMeta.map((entry) {
            final selected = _tool == entry.$1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _tool = entry.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        entry.$2,
                        size: 22,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.mutedText,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.mutedText,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Widget> _templatesSection(BuildContext context, ReceiptTemplate draft) {
    final saved = widget.templates
        .where((item) => !item.id.startsWith('builtin_'))
        .toList();
    return <Widget>[
      Text('Choose a design', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ReceiptTemplateType.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final type = ReceiptTemplateType.values[index];
            final spec = ReceiptTemplate.builtInSpec(type);
            final selected = draft.templateType == type;
            return _DesignCard(
              spec: spec,
              selected: selected,
              onTap: () => widget.onChanged(
                draft.copyWith(
                  templateType: type,
                  name: draft.id.startsWith('builtin_')
                      ? spec.name
                      : draft.name,
                  id: draft.id.startsWith('builtin_')
                      ? 'builtin_${type.name}'
                      : draft.id,
                  paperSize: spec.paperSize,
                  primaryColor: spec.primaryColor,
                  secondaryColor: spec.secondaryColor,
                  textColor: spec.textColor,
                  backgroundColor: spec.backgroundColor,
                  shadingStyle: type == ReceiptTemplateType.luxury
                      ? ReceiptShadingStyle.darkMesh
                      : type == ReceiptTemplateType.wave
                      ? ReceiptShadingStyle.softWave
                      : ReceiptShadingStyle.none,
                  headerAlignment: spec.headerAlignment,
                  logoShape: spec.logoShape,
                  showSignature: spec.showSignature,
                  clearShadingImage: true,
                  customHeader: spec.customHeader,
                  footerMessage: spec.footerMessage,
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      if (saved.isNotEmpty) ...<Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey('template-sel-${draft.id}'),
          initialValue: saved.any((item) => item.id == draft.id)
              ? draft.id
              : null,
          decoration: const InputDecoration(labelText: 'My saved templates'),
          items: saved
              .map(
                (item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
              )
              .toList(),
          onChanged: (id) {
            final selected = saved.where((item) => item.id == id).firstOrNull;
            if (selected != null) widget.onChanged(selected);
          },
        ),
        const SizedBox(height: 12),
      ],
      TextFormField(
        key: ValueKey('name-${draft.id}'),
        initialValue: draft.name,
        decoration: const InputDecoration(labelText: 'Template name'),
        onChanged: (value) => widget.onChanged(draft.copyWith(name: value)),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ReceiptPaperSize>(
        key: ValueKey('paper-${draft.id}-${draft.paperSize.name}'),
        initialValue: draft.paperSize,
        decoration: const InputDecoration(labelText: 'Paper size'),
        items: ReceiptPaperSize.values
            .map(
              (size) =>
                  DropdownMenuItem(value: size, child: Text(_paperLabel(size))),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) widget.onChanged(draft.copyWith(paperSize: value));
        },
      ),
      const Divider(height: 24),
      ..._toggles(draft, widget.onChanged),
      TextFormField(
        key: ValueKey('header-${draft.id}'),
        initialValue: draft.customHeader,
        decoration: const InputDecoration(labelText: 'Custom header'),
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(customHeader: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('footer-${draft.id}'),
        initialValue: draft.footerMessage,
        decoration: const InputDecoration(labelText: 'Footer message'),
        maxLines: 2,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(footerMessage: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('terms-${draft.id}'),
        initialValue: draft.termsText,
        decoration: const InputDecoration(labelText: 'Terms'),
        maxLines: 2,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(termsText: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('return-${draft.id}'),
        initialValue: draft.returnPolicy,
        decoration: const InputDecoration(labelText: 'Return policy'),
        maxLines: 2,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(returnPolicy: value)),
      ),
    ];
  }

  List<Widget> _colorSection(ReceiptTemplate draft) {
    return <Widget>[
      _ColorControl(
        label: 'Primary color',
        value: draft.primaryColor,
        swatches: <String>{
          widget.brandPrimary,
          '#5B3DF5',
          '#0F4C81',
          '#0D9488',
          '#DC2626',
          '#1E1B4B',
          '#8C5E3C',
          '#111827',
        },
        onChanged: (color) =>
            widget.onChanged(draft.copyWith(primaryColor: color)),
      ),
      _ColorControl(
        label: 'Secondary / accent color',
        value: draft.secondaryColor,
        swatches: <String>{
          widget.brandSecondary,
          '#10B981',
          '#C9A227',
          '#DB2777',
          '#F59E0B',
          '#38BDF8',
          '#D4B08C',
          '#374151',
        },
        onChanged: (color) =>
            widget.onChanged(draft.copyWith(secondaryColor: color)),
      ),
      _ColorControl(
        label: 'Text color',
        value: draft.textColor,
        swatches: <String>{widget.brandText, '#111827', '#374151', '#1F2937'},
        onChanged: (color) =>
            widget.onChanged(draft.copyWith(textColor: color)),
      ),
      _ColorControl(
        label: 'Background color',
        value: draft.backgroundColor,
        swatches: const <String>{
          '#FFFFFF',
          '#FFFBF5',
          '#FDFDFB',
          '#F8FAFC',
          '#FEF9C3',
        },
        onChanged: (color) =>
            widget.onChanged(draft.copyWith(backgroundColor: color)),
      ),
      const SizedBox(height: 4),
      Text('Alpha ${(draft.accentAlpha * 100).round()}%'),
      Slider(
        value: draft.accentAlpha.clamp(0.2, 1.0),
        min: 0.2,
        max: 1,
        divisions: 16,
        label: '${(draft.accentAlpha * 100).round()}%',
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(accentAlpha: value)),
      ),
      TextButton(
        onPressed: widget.onResetBranding,
        child: const Text('Reset to business branding'),
      ),
    ];
  }

  List<Widget> _logoSection(ReceiptTemplate draft) {
    String label(ReceiptLogoSize value) => switch (value) {
      ReceiptLogoSize.small => 'S',
      ReceiptLogoSize.medium => 'M',
      ReceiptLogoSize.large => 'L',
      ReceiptLogoSize.xlarge => 'XL',
    };
    return <Widget>[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show logo'),
        value: draft.logoEnabled,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(logoEnabled: value)),
      ),
      const SizedBox(height: 8),
      Text('Logo size', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<ReceiptLogoSize>(
        segments: ReceiptLogoSize.values
            .map(
              (item) => ButtonSegment<ReceiptLogoSize>(
                value: item,
                label: Text(label(item)),
              ),
            )
            .toList(),
        selected: <ReceiptLogoSize>{draft.logoSize},
        onSelectionChanged: (value) {
          widget.onChanged(draft.copyWith(logoSize: value.first));
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ReceiptLogoShape>(
        key: ValueKey('logo-shape-${draft.id}-${draft.logoShape.name}'),
        initialValue: draft.logoShape,
        decoration: const InputDecoration(labelText: 'Logo shape'),
        items: ReceiptLogoShape.values
            .map(
              (shape) =>
                  DropdownMenuItem(value: shape, child: Text(shape.name)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) widget.onChanged(draft.copyWith(logoShape: value));
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<ReceiptAlignment>(
        key: ValueKey('align-${draft.id}-${draft.headerAlignment.name}'),
        initialValue: draft.headerAlignment,
        decoration: const InputDecoration(labelText: 'Logo position'),
        items: ReceiptAlignment.values
            .map(
              (align) =>
                  DropdownMenuItem(value: align, child: Text(align.name)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            widget.onChanged(draft.copyWith(headerAlignment: value));
          }
        },
      ),
    ];
  }

  List<Widget> _fontSection(ReceiptTemplate draft) {
    ReceiptTemplate preset(ReceiptTemplate base, String size) => switch (size) {
      'S' => base.copyWith(
        businessNameFontSize: 14,
        bodyFontSize: 10,
        totalFontSize: 13,
      ),
      'M' => base.copyWith(
        businessNameFontSize: 18,
        bodyFontSize: 12,
        totalFontSize: 16,
      ),
      'L' => base.copyWith(
        businessNameFontSize: 22,
        bodyFontSize: 14,
        totalFontSize: 20,
      ),
      _ => base.copyWith(
        businessNameFontSize: 26,
        bodyFontSize: 16,
        totalFontSize: 24,
      ),
    };
    return <Widget>[
      Text('Quick size', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment(value: 'S', label: Text('S')),
          ButtonSegment(value: 'M', label: Text('M')),
          ButtonSegment(value: 'L', label: Text('L')),
          ButtonSegment(value: 'XL', label: Text('XL')),
        ],
        selected: <String>{'M'},
        onSelectionChanged: (value) {
          widget.onChanged(preset(draft, value.first));
        },
      ),
      const SizedBox(height: 12),
      Text('Title ${draft.businessNameFontSize.toStringAsFixed(0)}'),
      Slider(
        value: draft.businessNameFontSize.clamp(12, 30),
        min: 12,
        max: 30,
        divisions: 18,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(businessNameFontSize: value)),
      ),
      Text('Body ${draft.bodyFontSize.toStringAsFixed(0)}'),
      Slider(
        value: draft.bodyFontSize.clamp(9, 20),
        min: 9,
        max: 20,
        divisions: 11,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(bodyFontSize: value)),
      ),
      Text('Invoice info ${draft.totalFontSize.toStringAsFixed(0)}'),
      Slider(
        value: draft.totalFontSize.clamp(11, 28),
        min: 11,
        max: 28,
        divisions: 17,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(totalFontSize: value)),
      ),
    ];
  }

  List<Widget> _shadingSection(ReceiptTemplate draft) {
    final styles = ReceiptShadingStyle.values;
    final cloudBackgrounds = widget.shadingBackgrounds;
    String label(ReceiptShadingStyle style) => switch (style) {
      ReceiptShadingStyle.none => 'Plain',
      ReceiptShadingStyle.softWave => 'Soft curves',
      ReceiptShadingStyle.darkMesh => 'Mesh blend',
      ReceiptShadingStyle.cornerGlow => 'Corner glow',
      ReceiptShadingStyle.auroraMist => 'Aurora mist',
      ReceiptShadingStyle.diagonalSweep => 'Diagonal sweep',
      ReceiptShadingStyle.sunsetBloom => 'Sunset bloom',
      ReceiptShadingStyle.paperTexture => 'Paper texture',
    };

    Widget card(ReceiptShadingStyle style, bool selected) {
      final p = _parseColor(draft.primaryColor).withValues(alpha: 0.7);
      final s = _parseColor(draft.secondaryColor).withValues(alpha: 0.7);
      final imageAsset = _shadingAssetPath(style);
      BoxDecoration decoration;
      switch (style) {
        case ReceiptShadingStyle.none:
          decoration = const BoxDecoration(color: Colors.white);
        case ReceiptShadingStyle.softWave:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[p.withValues(alpha: 0.24), s.withValues(alpha: 0.18), p.withValues(alpha: 0.1)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(999),
          );
        case ReceiptShadingStyle.darkMesh:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[p.withValues(alpha: 0.22), Colors.transparent, s.withValues(alpha: 0.18)],
              stops: const <double>[0, 0.52, 1],
            ),
          );
        case ReceiptShadingStyle.cornerGlow:
          decoration = BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, -1),
              radius: 1.1,
              colors: <Color>[p.withValues(alpha: 0.22), Colors.transparent],
            ),
          );
        case ReceiptShadingStyle.auroraMist:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                p.withValues(alpha: 0.22),
                Colors.white,
                s.withValues(alpha: 0.2),
              ],
              stops: const <double>[0, 0.45, 1],
            ),
          );
        case ReceiptShadingStyle.diagonalSweep:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-1, -1),
              end: const Alignment(1, 1),
              colors: <Color>[
                p.withValues(alpha: 0.22),
                Colors.transparent,
                s.withValues(alpha: 0.18),
              ],
              stops: const <double>[0.08, 0.5, 0.92],
            ),
          );
        case ReceiptShadingStyle.sunsetBloom:
          decoration = BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.1, -1),
              radius: 1.35,
              colors: <Color>[
                s.withValues(alpha: 0.28),
                p.withValues(alpha: 0.14),
                Colors.transparent,
              ],
              stops: const <double>[0, 0.45, 1],
            ),
          );
        case ReceiptShadingStyle.paperTexture:
          decoration = BoxDecoration(
            color: const Color(0xFFFFFCF7),
            border: Border.all(color: p.withValues(alpha: 0.22), width: 0.8),
          );
      }

      if (imageAsset != null) {
        decoration = BoxDecoration(
          image: DecorationImage(
            image: AssetImage(imageAsset),
            fit: BoxFit.cover,
            opacity: 0.8,
          ),
        );
      }
      return Container(
        width: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _parseColor(draft.primaryColor) : context.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: Container(decoration: decoration)),
              Center(
                child: Text(
                  label(style),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return <Widget>[
      Text('Background shading', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: styles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final style = styles[index];
            final selected =
                (draft.shadingImageUrl?.trim().isEmpty ?? true) &&
                draft.shadingStyle == style;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  widget.onChanged(
                    draft.copyWith(
                      shadingStyle: style,
                      clearShadingImage: true,
                    ),
                  ),
              child: card(style, selected),
            );
          },
        ),
      ),
      if (cloudBackgrounds.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        Text('Cloud backgrounds', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cloudBackgrounds.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = cloudBackgrounds[index];
              final selected = draft.shadingImageUrl?.trim() == item.imageUrl;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    widget.onChanged(
                      draft.copyWith(
                        shadingStyle: ReceiptShadingStyle.none,
                        shadingImageUrl: item.imageUrl,
                      ),
                    ),
                child: Container(
                  width: 126,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? _parseColor(draft.primaryColor)
                          : context.borderColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.network(
                          item.thumbnailUrl?.trim().isNotEmpty == true
                              ? item.thumbnailUrl!.trim()
                              : item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFF8FAFC),
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.42),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  List<Widget> _signatureSection(ReceiptTemplate draft) {
    Future<void> pickSignature() async {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      final base64 = base64Encode(bytes);
      if (!mounted) return;
      widget.onChanged(
        draft.copyWith(
          showSignature: true,
          signatureMode: ReceiptSignatureMode.upload,
          signatureImageBase64: base64,
        ),
      );
    }

    Future<void> openSignaturePad() async {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: _SignatureCaptureSheet(
            initialSignatureBase64: draft.signatureImageBase64,
          ),
        ),
      );
      if (result == null || result.isEmpty || !mounted) return;
      widget.onChanged(
        draft.copyWith(
          showSignature: true,
          signatureMode: ReceiptSignatureMode.draw,
          signatureImageBase64: result,
        ),
      );
    }

    return <Widget>[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show signature area'),
        subtitle: const Text(
          'Displays a signature box in the receipt preview/PDF.',
        ),
        value: draft.showSignature,
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(showSignature: value)),
      ),
      const SizedBox(height: 4),
      SegmentedButton<ReceiptSignatureMode>(
        segments: const <ButtonSegment<ReceiptSignatureMode>>[
          ButtonSegment(
            value: ReceiptSignatureMode.placeholder,
            label: Text('Placeholder'),
          ),
          ButtonSegment(value: ReceiptSignatureMode.draw, label: Text('Draw')),
          ButtonSegment(
            value: ReceiptSignatureMode.upload,
            label: Text('Upload'),
          ),
        ],
        selected: <ReceiptSignatureMode>{draft.signatureMode},
        onSelectionChanged: (value) {
          widget.onChanged(draft.copyWith(signatureMode: value.first));
        },
      ),
      const SizedBox(height: 10),
      if (draft.signatureMode == ReceiptSignatureMode.draw)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Large signing board',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Open a full-screen signature pad for easier signing.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: openSignaturePad,
                icon: const Icon(Icons.draw_outlined),
                label: Text(
                  draft.signatureImageBase64 != null &&
                          draft.signatureImageBase64!.isNotEmpty
                      ? 'Edit signature'
                      : 'Open signature pad',
                ),
              ),
            ],
          ),
        ),
      if (draft.signatureMode == ReceiptSignatureMode.upload)
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pickSignature,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload signature'),
              ),
            ),
          ],
        ),
      if (draft.signatureImageBase64 != null &&
          draft.signatureImageBase64!.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        Container(
          height: 88,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          alignment: Alignment.center,
          child: Image.memory(
            base64Decode(draft.signatureImageBase64!),
            fit: BoxFit.contain,
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Signature size ${(draft.signatureScale * 100).round()}%',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Slider(
        value: draft.signatureScale.clamp(0.7, 1.8),
        min: 0.7,
        max: 1.8,
        divisions: 11,
        label: '${(draft.signatureScale * 100).round()}%',
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(signatureScale: value)),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFEAB308)),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFFFFBEB),
        ),
        child: const Text('Your signature will appear on the receipt preview and PDF.'),
      ),
    ];
  }

  List<Widget> _paidStampSection(ReceiptTemplate draft) {
    return <Widget>[
      DropdownButtonFormField<ReceiptPaidStampMode>(
        key: ValueKey(
          'paid-stamp-mode-${draft.id}-${draft.paidStampMode.name}',
        ),
        initialValue: draft.paidStampMode,
        decoration: const InputDecoration(labelText: 'Paid stamp visibility'),
        items: ReceiptPaidStampMode.values
            .map(
              (mode) => DropdownMenuItem(value: mode, child: Text(mode.name)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            widget.onChanged(draft.copyWith(paidStampMode: value));
          }
        },
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('paid-text-${draft.id}'),
        initialValue: draft.paidStampText,
        decoration: const InputDecoration(labelText: 'Paid text'),
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(paidStampText: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('unpaid-text-${draft.id}'),
        initialValue: draft.unpaidStampText,
        decoration: const InputDecoration(labelText: 'Unpaid text'),
        onChanged: (value) =>
            widget.onChanged(draft.copyWith(unpaidStampText: value)),
      ),
    ];
  }

  List<Widget> _toggles(
    ReceiptTemplate draft,
    ValueChanged<ReceiptTemplate> onChanged,
  ) {
    final items = <(String, bool, ReceiptTemplate Function(bool))>[
      (
        'Business name',
        draft.showBusinessName,
        (v) => draft.copyWith(showBusinessName: v),
      ),
      (
        'Phone',
        draft.showBusinessPhone,
        (v) => draft.copyWith(showBusinessPhone: v),
      ),
      (
        'Email',
        draft.showBusinessEmail,
        (v) => draft.copyWith(showBusinessEmail: v),
      ),
      (
        'Address',
        draft.showBusinessAddress,
        (v) => draft.copyWith(showBusinessAddress: v),
      ),
      ('Website', draft.showWebsite, (v) => draft.copyWith(showWebsite: v)),
      ('Customer', draft.showCustomer, (v) => draft.copyWith(showCustomer: v)),
      ('Cashier', draft.showCashier, (v) => draft.copyWith(showCashier: v)),
      ('SKU', draft.showSku, (v) => draft.copyWith(showSku: v)),
      (
        'Unit price',
        draft.showUnitPrice,
        (v) => draft.copyWith(showUnitPrice: v),
      ),
      ('Discount', draft.showDiscount, (v) => draft.copyWith(showDiscount: v)),
      ('Tax', draft.showTax, (v) => draft.copyWith(showTax: v)),
      (
        'Payment details',
        draft.showPaymentDetails,
        (v) => draft.copyWith(showPaymentDetails: v),
      ),
      ('Notes', draft.showNotes, (v) => draft.copyWith(showNotes: v)),
      ('QR code', draft.showQrCode, (v) => draft.copyWith(showQrCode: v)),
    ];
    return items
        .map(
          (item) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.$1),
            value: item.$2,
            onChanged: (value) => onChanged(item.$3(value)),
          ),
        )
        .toList();
  }

  String _paperLabel(ReceiptPaperSize size) => switch (size) {
    ReceiptPaperSize.thermal58 => '58mm thermal',
    ReceiptPaperSize.thermal80 => '80mm thermal',
    ReceiptPaperSize.a4 => 'A4 PDF',
    ReceiptPaperSize.digital => 'Mobile digital',
  };
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final ReceiptBuiltInSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = _parseColor(spec.primaryColor);
    final secondary = _parseColor(spec.secondaryColor);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.08)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : context.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 26,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: <Color>[primary, secondary]),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 5, width: 90, color: const Color(0xFFE5E7EB)),
            const SizedBox(height: 3),
            Container(height: 5, width: 60, color: const Color(0xFFE5E7EB)),
            const Spacer(),
            Text(
              spec.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            Text(
              spec.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({
    required this.label,
    required this.value,
    required this.swatches,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Set<String> swatches;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: swatches.map((color) {
              final selected = value.toUpperCase() == color.toUpperCase();
              return InkWell(
                onTap: () => onChanged(color.toUpperCase()),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _parseColor(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Colors.black87
                          : const Color(0xFFE5E7EB),
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('hex-$label-$value'),
            initialValue: value,
            decoration: InputDecoration(
              labelText: '$label hex',
              hintText: '#5B3DF5',
              isDense: true,
            ),
            onChanged: (raw) {
              final cleaned = raw.trim();
              if (RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(cleaned)) {
                final hex = cleaned.startsWith('#') ? cleaned : '#$cleaned';
                onChanged(hex.toUpperCase());
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SignatureCaptureSheet extends StatefulWidget {
  const _SignatureCaptureSheet({this.initialSignatureBase64});

  final String? initialSignatureBase64;

  @override
  State<_SignatureCaptureSheet> createState() => _SignatureCaptureSheetState();
}

class _SignatureCaptureSheetState extends State<_SignatureCaptureSheet> {
  final List<_SignatureStroke> _strokes = <_SignatureStroke>[];
  List<Offset> _activeStroke = <Offset>[];

  Future<void> _saveDrawnSignature() async {
    if (_strokes.isEmpty && _activeStroke.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw a signature first.')),
      );
      return;
    }

    final allStrokes = <_SignatureStroke>[
      ..._strokes,
      if (_activeStroke.isNotEmpty) _SignatureStroke(_activeStroke),
    ];
    final allPoints = allStrokes
        .expand((stroke) => stroke.points)
        .toList(growable: false);
    if (allPoints.isEmpty) return;

    var minX = allPoints.first.dx;
    var minY = allPoints.first.dy;
    var maxX = allPoints.first.dx;
    var maxY = allPoints.first.dy;
    for (final point in allPoints.skip(1)) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const padding = 24.0;
    final width = (maxX - minX + (padding * 2)).clamp(240.0, 1600.0);
    final height = (maxY - minY + (padding * 2)).clamp(120.0, 900.0);
    final size = Size(width, height);
    final bg = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, bg);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in allStrokes) {
      for (var i = 0; i < stroke.points.length - 1; i++) {
        final p1 = Offset(
          stroke.points[i].dx - minX + padding,
          stroke.points[i].dy - minY + padding,
        );
        final p2 = Offset(
          stroke.points[i + 1].dx - minX + padding,
          stroke.points[i + 1].dy - minY + padding,
        );
        canvas.drawLine(p1, p2, paint);
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || data == null) return;
    final bytes = data.buffer.asUint8List();
    Navigator.pop(context, base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Sign here'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              setState(() {
                _strokes.clear();
                _activeStroke = <Offset>[];
              });
            },
            child: const Text('Clear'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.edit_note_outlined, color: Color(0xFF5B3DF5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use the wide white board below to sign comfortably on your phone.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(
                        () => _activeStroke = <Offset>[
                          details.localPosition,
                        ],
                      );
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _activeStroke = <Offset>[
                          ..._activeStroke,
                          details.localPosition,
                        ];
                      });
                    },
                    onPanEnd: (_) {
                      if (_activeStroke.isEmpty) return;
                      setState(() {
                        _strokes.add(_SignatureStroke(_activeStroke));
                        _activeStroke = <Offset>[];
                      });
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          strokes: _strokes,
                          activeStroke: _activeStroke,
                        ),
                        child: Center(
                          child: (_strokes.isEmpty && _activeStroke.isEmpty)
                              ? const Text(
                                  'Sign here',
                                  style: TextStyle(
                                    color: AppColors.mutedText,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveDrawnSignature,
                      child: const Text('Use signature'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required this.activeStroke});

  final List<_SignatureStroke> strokes;
  final List<Offset> activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (var i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }
    for (var i = 0; i < activeStroke.length - 1; i++) {
      canvas.drawLine(activeStroke[i], activeStroke[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.activeStroke != activeStroke;
  }
}

class _PaperTexturePainter extends CustomPainter {
  const _PaperTexturePainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = primary;
    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = secondary;

    const step = 18.0;
    for (double y = 10; y < size.height; y += step) {
      final wobble = (y / 17) % 2 == 0 ? 3.0 : -3.0;
      final path = Path()
        ..moveTo(0, y + wobble)
        ..quadraticBezierTo(size.width * 0.45, y - wobble, size.width, y + wobble);
      canvas.drawPath(path, thin);
    }

    for (double x = 12; x < size.width; x += 34) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + 10, size.height),
        soft,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.secondary != secondary;
  }
}
