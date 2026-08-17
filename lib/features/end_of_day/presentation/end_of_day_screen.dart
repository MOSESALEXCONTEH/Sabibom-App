import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/presentation/team_widgets.dart';
import '../data/end_of_day_repository.dart';

final endOfDayRepositoryProvider = Provider<EndOfDayRepository>((ref) {
  return EndOfDayRepository();
});

class EndOfDayScreen extends ConsumerStatefulWidget {
  const EndOfDayScreen({this.dateKey, super.key});

  final String? dateKey;

  @override
  ConsumerState<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends ConsumerState<EndOfDayScreen> {
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  var _loading = true;
  var _saving = false;
  EndOfDaySummary? _summary;
  EndOfDayCashBreakdown? _breakdown;
  String? _error;

  String get _dateKey =>
      widget.dateKey ?? EndOfDayRepository.dateKeyFor(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _opening.dispose();
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      setState(() {
        _loading = false;
        _error = 'Select a business first.';
      });
      return;
    }
    final businessId = active.business.businessId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(endOfDayRepositoryProvider);
      final existing = await repo.get(businessId, _dateKey);
      final breakdown = await repo.loadCashBreakdown(
        businessId: businessId,
        dateKey: _dateKey,
      );
      if (!mounted) return;
      setState(() {
        _summary = existing;
        _breakdown = breakdown;
        if (existing != null) {
          _opening.text = (existing.openingCashMinor / 100).toStringAsFixed(2);
          _counted.text = (existing.countedCashMinor / 100).toStringAsFixed(2);
          _notes.text = existing.notes ?? '';
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load End of Day. Check your connection and try again.';
      });
    }
  }

  int _parseMinor(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '')) ?? 0;
    if (!value.isFinite || value < 0) return 0;
    return (value * 100).round();
  }

  Future<void> _save({required bool finalize}) async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(endOfDayRepositoryProvider);
      final summary = finalize
          ? await repo.finalize(
              businessId: active.business.businessId,
              dateKey: _dateKey,
              openingCashMinor: _parseMinor(_opening.text),
              countedCashMinor: _parseMinor(_counted.text),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            )
          : await repo.saveDraft(
              businessId: active.business.businessId,
              dateKey: _dateKey,
              openingCashMinor: _parseMinor(_opening.text),
              countedCashMinor: _parseMinor(_counted.text),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );
      if (!mounted) return;
      setState(() => _summary = summary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            finalize ? 'End of Day finalized.' : 'End of Day draft saved.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Something went wrong. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reopen() async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) return;
    setState(() => _saving = true);
    try {
      final summary = await ref
          .read(endOfDayRepositoryProvider)
          .reopen(businessId: active.business.businessId, dateKey: _dateKey);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reopen End of Day.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sharePdf() async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    final summary = _summary;
    if (active is! ActiveBusinessData || summary == null) return;
    final biz = active.business;
    String money(int m) =>
        formatCurrency(minorToMoney(m), symbol: biz.currency.symbol);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            biz.name,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('End of Day · ${summary.dateKey}'),
          pw.SizedBox(height: 16),
          pw.Text('Opening cash: ${money(summary.openingCashMinor)}'),
          pw.Text('Cash sales: ${money(summary.cashSalesMinor)}'),
          pw.Text(
            'Customer cash payments: ${money(summary.cashCustomerPaymentsMinor)}',
          ),
          pw.Text('Cash expenses: ${money(summary.cashExpensesMinor)}'),
          pw.Text(
            'Supplier cash payments: ${money(summary.cashSupplierPaymentsMinor)}',
          ),
          pw.Text('Expected cash: ${money(summary.expectedCashMinor)}'),
          pw.Text('Counted cash: ${money(summary.countedCashMinor)}'),
          pw.Text(
            '${summary.differenceKind.label}: ${money(summary.differenceMinor.abs())}',
          ),
          pw.Text('Status: ${summary.status.storedValue}'),
        ],
      ),
    );
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/SabiBom_End_Of_Day_${summary.dateKey}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'End of Day ${summary.dateKey}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canView =
        ref.watch(hasPermissionProvider(AppPermission.viewEndOfDayAlerts)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewSalesReports));
    if (!canView) {
      return const AccessDeniedScreen(
        message: 'You do not have permission to view End of Day.',
      );
    }
    final canReopen =
        ref.watch(
          hasPermissionProvider(AppPermission.approveSensitiveActions),
        ) ||
        ref.watch(currentBusinessMembershipProvider).asData?.value?.isOwner ==
            true;
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final symbol = active is ActiveBusinessData
        ? active.business.currency.symbol
        : 'Le';
    final locked = _summary?.isFinalized == true;

    return Scaffold(
      appBar: AppBar(
        title: Text('End of Day · $_dateKey'),
        actions: [
          if (_summary != null)
            IconButton(
              tooltip: 'Share PDF',
              onPressed: _sharePdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  AppCardSkeleton(height: 80),
                  SizedBox(height: AppSpacing.md),
                  AppCardSkeleton(height: 160),
                  SizedBox(height: AppSpacing.md),
                  AppCardSkeleton(height: 120),
                ],
              ),
            )
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: appSafeScrollPadding(context),
              children: [
                Text(
                  'Only cash movements affect expected physical cash. '
                  'Mobile Money, card and bank transfer are excluded.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_breakdown != null) ...[
                  _row(
                    'Cash sales',
                    _money(_breakdown!.cashSalesMinor, symbol),
                  ),
                  _row(
                    'Customer cash payments',
                    _money(_breakdown!.cashCustomerPaymentsMinor, symbol),
                  ),
                  _row(
                    'Cash expenses',
                    _money(_breakdown!.cashExpensesMinor, symbol),
                  ),
                  _row(
                    'Supplier cash payments',
                    _money(_breakdown!.cashSupplierPaymentsMinor, symbol),
                  ),
                  const Divider(),
                ],
                TextField(
                  controller: _opening,
                  enabled: !locked && !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Opening cash ($symbol)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _counted,
                  enabled: !locked && !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Counted cash ($symbol)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  enabled: !locked && !_saving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _PreviewCard(
                  openingMinor: _parseMinor(_opening.text),
                  countedMinor: _parseMinor(_counted.text),
                  breakdown: _breakdown,
                  symbol: symbol,
                  saved: _summary,
                ),
                if (locked) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Finalized${_summary?.finalizedAt != null ? ' · ${DateFormat.yMMMd().add_jm().format(_summary!.finalizedAt!)}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!locked) ...[
                  Semantics(
                    button: true,
                    label: 'Save end of day draft',
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(finalize: false),
                      child: Text(_saving ? 'Saving…' : 'Save draft'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: 'Finalize end of day',
                    child: FilledButton.tonal(
                      onPressed: _saving ? null : () => _save(finalize: true),
                      child: const Text('Finalize End of Day'),
                    ),
                  ),
                ] else if (canReopen) ...[
                  Semantics(
                    button: true,
                    label: 'Reopen finalized end of day',
                    child: OutlinedButton(
                      onPressed: _saving ? null : _reopen,
                      child: const Text('Reopen summary'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _money(int minor, String symbol) =>
      formatCurrency(minorToMoney(minor), symbol: symbol);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.openingMinor,
    required this.countedMinor,
    required this.breakdown,
    required this.symbol,
    this.saved,
  });

  final int openingMinor;
  final int countedMinor;
  final EndOfDayCashBreakdown? breakdown;
  final String symbol;
  final EndOfDaySummary? saved;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final expected = EndOfDayCalculator.expectedCashMinor(
      openingCashMinor: openingMinor,
      cashSalesMinor: b?.cashSalesMinor ?? saved?.cashSalesMinor ?? 0,
      cashCustomerPaymentsMinor:
          b?.cashCustomerPaymentsMinor ?? saved?.cashCustomerPaymentsMinor ?? 0,
      cashExpensesMinor: b?.cashExpensesMinor ?? saved?.cashExpensesMinor ?? 0,
      cashSupplierPaymentsMinor:
          b?.cashSupplierPaymentsMinor ?? saved?.cashSupplierPaymentsMinor ?? 0,
    );
    final diff = EndOfDayCalculator.differenceMinor(
      countedCashMinor: countedMinor,
      expectedCashMinor: expected,
    );
    final kind = CashDifferenceKind.fromDifference(diff);
    String money(int m) => formatCurrency(minorToMoney(m), symbol: symbol);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expected cash: ${money(expected)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Counted cash: ${money(countedMinor)}'),
            const SizedBox(height: 4),
            Text(
              '${kind.label}: ${money(diff.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kind == CashDifferenceKind.balanced
                    ? Colors.green.shade700
                    : kind == CashDifferenceKind.shortage
                    ? Colors.red.shade700
                    : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
