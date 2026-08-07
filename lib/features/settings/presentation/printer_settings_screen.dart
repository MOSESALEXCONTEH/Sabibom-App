import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';

/// Printer and receipt output preferences for this device and business.
class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  var _paperWidth = '80mm';
  var _autoPrint = false;
  var _openAfterSale = true;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _paperWidth = prefs.getString('printer_paper_width') ?? '80mm';
      _autoPrint = prefs.getBool('printer_auto_print') ?? false;
      _openAfterSale = prefs.getBool('printer_open_after_sale') ?? true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final businessId =
        ref.watch(currentUserProfileProvider).asData?.value?.activeBusinessId;

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: <Widget>[
                Text(
                  'Choose how receipts are prepared for thermal printers and '
                  'PDF sharing. Pairing a Bluetooth printer will be added next.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _paperWidth,
                  decoration: const InputDecoration(
                    labelText: 'Receipt paper width',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: '58mm', child: Text('58 mm (compact)')),
                    DropdownMenuItem(value: '80mm', child: Text('80 mm (standard)')),
                    DropdownMenuItem(value: 'A4', child: Text('A4 / PDF share')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _paperWidth = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Open receipt after each sale'),
                  subtitle: const Text(
                    'Shows the receipt screen so you can print or share quickly.',
                  ),
                  value: _openAfterSale,
                  onChanged: (value) => setState(() => _openAfterSale = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print when ready'),
                  subtitle: const Text(
                    'Attempts to print automatically once a printer is connected.',
                  ),
                  value: _autoPrint,
                  onChanged: (value) => setState(() => _autoPrint = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _save(businessId),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save printer preferences'),
                ),
              ],
            ),
    );
  }

  Future<void> _save(String? businessId) async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_paper_width', _paperWidth);
      await prefs.setBool('printer_auto_print', _autoPrint);
      await prefs.setBool('printer_open_after_sale', _openAfterSale);
      if (businessId != null && businessId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .set(<String, Object?>{
              'printerPaperWidth': _paperWidth,
              'printerAutoPrint': _autoPrint,
              'printerOpenAfterSale': _openAfterSale,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer preferences saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
