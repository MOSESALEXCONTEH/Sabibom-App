import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/data/push_notification_bootstrap.dart';
import '../../setup/domain/setup_checklist.dart';

/// Explicit-save notification preferences (Checkpoint 2).
class NotificationsSettingsScreen extends ConsumerStatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  ConsumerState<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends ConsumerState<NotificationsSettingsScreen> {
  NotificationPreferences _draft = const NotificationPreferences();
  NotificationPreferences _saved = const NotificationPreferences();
  var _hydrated = false;
  var _saving = false;

  bool get _dirty =>
      _draft.inAppEnabled != _saved.inAppEnabled ||
      _draft.pushEnabled != _saved.pushEnabled ||
      _draft.lowStockEnabled != _saved.lowStockEnabled ||
      _draft.outOfStockEnabled != _saved.outOfStockEnabled ||
      _draft.customerDebtEnabled != _saved.customerDebtEnabled ||
      _draft.supplierPaymentEnabled != _saved.supplierPaymentEnabled ||
      _draft.approvalEnabled != _saved.approvalEnabled ||
      _draft.endOfDayEnabled != _saved.endOfDayEnabled ||
      _draft.largeExpenseEnabled != _saved.largeExpenseEnabled ||
      _draft.staffActivityEnabled != _saved.staffActivityEnabled ||
      _draft.dailySummaryEnabled != _saved.dailySummaryEnabled ||
      _draft.weeklyReportEnabled != _saved.weeklyReportEnabled ||
      _draft.dailySummaryTime != _saved.dailySummaryTime ||
      _draft.weeklyReportDay != _saved.weeklyReportDay ||
      _draft.weeklyReportTime != _saved.weeklyReportTime ||
      _draft.endOfDayReminderTime != _saved.endOfDayReminderTime ||
      _draft.quietHoursEnabled != _saved.quietHoursEnabled ||
      _draft.quietHoursStart != _saved.quietHoursStart ||
      _draft.quietHoursEnd != _saved.quietHoursEnd ||
      _draft.customerDebtMinimumMinor != _saved.customerDebtMinimumMinor ||
      _draft.supplierDebtMinimumMinor != _saved.supplierDebtMinimumMinor ||
      _draft.largeExpenseThresholdMinor != _saved.largeExpenseThresholdMinor;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to manage notifications.')),
      );
    }

    final canManage = true; // Personal preferences — always editable by owner.

    final prefsAsync = ref.watch(notificationPreferencesProvider);
    prefsAsync.whenData((prefs) {
      if (!_hydrated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _hydrated) return;
          setState(() {
            _draft = prefs;
            _saved = prefs;
            _hydrated = true;
          });
        });
      }
    });

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
              'You have unsaved notification preferences. Discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Choose which alerts you want. Preferences save only when you tap Save.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            _section('General'),
            _switch(
              'In-app notifications',
              _draft.inAppEnabled,
              (v) => setState(() => _draft = _draft.copyWith(inAppEnabled: v)),
            ),
            _switch(
              'Push notifications',
              _draft.pushEnabled,
              (v) => setState(() => _draft = _draft.copyWith(pushEnabled: v)),
            ),
            _switch(
              'Quiet hours',
              _draft.quietHoursEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(quietHoursEnabled: v),
              ),
            ),
            if (_draft.quietHoursEnabled) ...[
              _timeTile(
                'Quiet hours start',
                _draft.quietHoursStart,
                (v) => setState(
                  () => _draft = _draft.copyWith(quietHoursStart: v),
                ),
              ),
              _timeTile(
                'Quiet hours end',
                _draft.quietHoursEnd,
                (v) =>
                    setState(() => _draft = _draft.copyWith(quietHoursEnd: v)),
              ),
            ],
            _section('Inventory'),
            _switch(
              'Low-stock alerts',
              _draft.lowStockEnabled,
              (v) =>
                  setState(() => _draft = _draft.copyWith(lowStockEnabled: v)),
            ),
            _switch(
              'Out-of-stock alerts',
              _draft.outOfStockEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(outOfStockEnabled: v),
              ),
            ),
            _section('Customers'),
            _switch(
              'Customer debt alerts',
              _draft.customerDebtEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(customerDebtEnabled: v),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Minimum balance to alert'),
              subtitle: Text(
                formatCurrency(_draft.customerDebtMinimumMinor / 100),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editMinor(
                title: 'Customer debt minimum',
                current: _draft.customerDebtMinimumMinor,
                onSave: (v) => setState(
                  () => _draft = _draft.copyWith(customerDebtMinimumMinor: v),
                ),
              ),
            ),
            _section('Suppliers'),
            _switch(
              'Supplier payment alerts',
              _draft.supplierPaymentEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(supplierPaymentEnabled: v),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Minimum supplier balance'),
              subtitle: Text(
                formatCurrency(_draft.supplierDebtMinimumMinor / 100),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editMinor(
                title: 'Supplier debt minimum',
                current: _draft.supplierDebtMinimumMinor,
                onSave: (v) => setState(
                  () => _draft = _draft.copyWith(supplierDebtMinimumMinor: v),
                ),
              ),
            ),
            _section('Operations'),
            _switch(
              'Approval requests',
              _draft.approvalEnabled,
              (v) =>
                  setState(() => _draft = _draft.copyWith(approvalEnabled: v)),
            ),
            _switch(
              'End-of-Day reminders',
              _draft.endOfDayEnabled,
              (v) =>
                  setState(() => _draft = _draft.copyWith(endOfDayEnabled: v)),
            ),
            _timeTile(
              'End-of-Day reminder time',
              _draft.endOfDayReminderTime,
              (v) => setState(
                () => _draft = _draft.copyWith(endOfDayReminderTime: v),
              ),
            ),
            _switch(
              'Large-expense alerts',
              _draft.largeExpenseEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(largeExpenseEnabled: v),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Large expense threshold'),
              subtitle: Text(
                formatCurrency(_draft.largeExpenseThresholdMinor / 100),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editMinor(
                title: 'Large expense threshold',
                current: _draft.largeExpenseThresholdMinor,
                onSave: (v) => setState(
                  () => _draft = _draft.copyWith(largeExpenseThresholdMinor: v),
                ),
              ),
            ),
            _section('Reports'),
            _switch(
              'Daily summary',
              _draft.dailySummaryEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(dailySummaryEnabled: v),
              ),
            ),
            _timeTile(
              'Daily summary time',
              _draft.dailySummaryTime,
              (v) =>
                  setState(() => _draft = _draft.copyWith(dailySummaryTime: v)),
            ),
            _switch(
              'Weekly report',
              _draft.weeklyReportEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(weeklyReportEnabled: v),
              ),
            ),
            _timeTile(
              'Weekly report time',
              _draft.weeklyReportTime,
              (v) =>
                  setState(() => _draft = _draft.copyWith(weeklyReportTime: v)),
            ),
            _section('Staff'),
            _switch(
              'Staff activity alerts',
              _draft.staffActivityEnabled,
              (v) => setState(
                () => _draft = _draft.copyWith(staffActivityEnabled: v),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: (!canManage || _saving || !_dirty)
                  ? null
                  : () => _save(uid),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save notification preferences'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _timeTile(String title, String value, ValueChanged<String> onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.schedule),
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.first) ?? 18,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
        );
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked == null) return;
        final hh = picked.hour.toString().padLeft(2, '0');
        final mm = picked.minute.toString().padLeft(2, '0');
        onChanged('$hh:$mm');
      },
    );
  }

  Future<void> _editMinor({
    required String title,
    required int current,
    required ValueChanged<int> onSave,
  }) async {
    final controller = TextEditingController(
      text: (current / 100).toStringAsFixed(2),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'Le ',
            hintText: '0.00',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final major = double.tryParse(controller.text.trim());
              if (major == null || major < 0 || !major.isFinite) return;
              Navigator.pop(ctx, (major * 100).round());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _save(String uid) async {
    setState(() => _saving = true);
    try {
      final active = ref.read(activeBusinessProvider).asData?.value;
      final businessId = active is ActiveBusinessData
          ? active.business.businessId
          : null;
      await ref
          .read(notificationsRepositoryProvider)
          .savePreferences(userId: uid, businessId: businessId, prefs: _draft);
      final push = ref.read(pushNotificationBootstrapProvider);
      if (_draft.pushEnabled) {
        await push.registerCurrentUserToken();
      } else {
        await push.unregisterCurrentUserToken();
      }
      await SetupChecklistService().markNotificationPrefsSaved();
      if (!mounted) return;
      setState(() => _saved = _draft);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      final detail = error is FirebaseException
          ? (error.message?.trim().isNotEmpty == true
                ? error.message!
                : error.code)
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preferences: $detail')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
