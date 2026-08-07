import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../setup/application/setup_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/presentation/team_widgets.dart';
import '../data/business_backup_service.dart';

final businessBackupServiceProvider = Provider<BusinessBackupService>((ref) {
  return BusinessBackupService();
});

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  var _busy = false;
  List<File> _localBackups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLocal());
  }

  Future<void> _refreshLocal() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('SabiBom_Backup_') && f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (!mounted) return;
    setState(() => _localBackups = files.take(8).toList());
  }

  Future<void> _export() async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(businessBackupServiceProvider);
      final file = await service.exportBackup(active.business.businessId);
      await ref.read(setupChecklistServiceProvider).markFirstBackupDone();
      ref.invalidate(setupChecklistProvider);
      await _refreshLocal();
      var shared = true;
      try {
        await service.shareBackup(file);
      } catch (_) {
        shared = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'Backup created and ready to share.'
                : 'Backup saved on this device (${file.uri.pathSegments.last}). Share sheet unavailable.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not create backup: ${error is StateError ? error.message : error}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore as a new business?'),
        content: const Text(
          'SabiBom creates a new business from this backup. Your current '
          'business is not overwritten. Passwords and device tokens are never restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final newId =
          await ref.read(businessBackupServiceProvider).restoreAsNewBusiness(file);
      ref.invalidate(activeBusinessProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored as a new business ($newId).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not restore backup: ${error is StateError ? error.message : error}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(
          hasPermissionProvider(AppPermission.editBusinessSettings),
        ) ||
        ref.watch(currentBusinessMembershipProvider).asData?.value?.isOwner ==
            true;
    if (!canEdit) {
      return const AccessDeniedScreen(
        message: 'Only owners or managers can create or restore backups.',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup and Restore')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Export a JSON backup of products, customers, suppliers, expenses, '
            'sales, purchases and roles. Secrets and device tokens are excluded.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            button: true,
            label: 'Create and share business backup',
            child: FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.backup_outlined),
              label: Text(_busy ? 'Working…' : 'Create backup'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Recent backups on this device',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (_localBackups.isEmpty)
            const AppEmptyState(
              title: 'No local backups yet',
              description: 'Create one to get started.',
              icon: Icons.backup_outlined,
            )
          else
            ..._localBackups.map((file) {
              final name = file.uri.pathSegments.last;
              return AppListRow(
                leading: const AppListAvatar(icon: Icons.description_outlined),
                title: name,
                subtitle: 'Modified ${file.lastModifiedSync()}',
                trailing: const Icon(Icons.restore),
                onTap: _busy ? null : () => _restore(file),
              );
            }),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Restore always creates a new business. Review the restored data before '
            'using it for daily work.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
