import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_spacing.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/business_membership.dart';
import '../domain/staff_activity.dart';
import '../domain/system_roles.dart';
import '../domain/team_exception.dart';
import 'team_widgets.dart';

class InviteStaffScreen extends ConsumerStatefulWidget {
  const InviteStaffScreen({super.key});

  @override
  ConsumerState<InviteStaffScreen> createState() => _InviteStaffScreenState();
}

class _InviteStaffScreenState extends ConsumerState<InviteStaffScreen> {
  final _contactCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _roleId = SystemRoleIds.cashier;
  int _expiryDays = 7;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _contactCtrl.dispose();
    _nameCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _contactIsEmail => _contactCtrl.text.contains('@');

  Set<AppPermission> get _previewPermissions {
    final roles = ref.read(teamRolesProvider).asData?.value ?? const [];
    for (final r in roles) {
      if (r.id == _roleId) return r.permissions;
    }
    return SystemRoles.defaultPermissionsFor(_roleId);
  }

  Future<void> _submit() async {
    final contact = _contactCtrl.text.trim();
    if (contact.isEmpty) {
      setState(() => _error = 'Enter an email or phone number.');
      return;
    }
    if (_contactIsEmail &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(contact)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final businessId = ref.read(teamBusinessIdProvider);
    final business = ref.read(activeBusinessProvider).asData?.value;
    final actor = ref.read(currentBusinessMembershipProvider).asData?.value;
    if (uid == null || businessId == null || business is! ActiveBusinessData) {
      setState(() => _error = TeamException.noBusiness.message);
      return;
    }

    final me = FirebaseAuth.instance.currentUser;
    if (me?.email != null &&
        contact.toLowerCase() == me!.email!.toLowerCase()) {
      setState(() => _error = 'You cannot invite yourself.');
      return;
    }

    final members = ref.read(teamMembersProvider).asData?.value ?? [];
    final already = members.any((m) {
      if (m.status != MemberStatus.active) return false;
      if (_contactIsEmail) {
        return m.email?.toLowerCase() == contact.toLowerCase();
      }
      return m.phone == contact;
    });
    if (already) {
      setState(() => _error = TeamException.existingMember.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(teamRepositoryProvider);
      final roleName = SystemRoles.labelFor(_roleId);
      final permissions = _previewPermissions;
      final invitation = await repo.createInvitation(
        businessId: businessId,
        businessName: business.business.name,
        invitedBy: uid,
        invitedByName: actor?.effectiveDisplayName ??
            me?.displayName ??
            me?.email ??
            'Owner',
        roleId: _roleId,
        roleName: roleName,
        permissions: permissions,
        email: _contactIsEmail ? contact : null,
        phone: _contactIsEmail ? null : contact,
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        message: _messageCtrl.text.trim().isEmpty
            ? null
            : _messageCtrl.text.trim(),
        expiresIn: Duration(days: _expiryDays),
      );

      await repo.logActivity(
        StaffActivity(
          id: '',
          businessId: businessId,
          userId: uid,
          userName: actor?.effectiveDisplayName ?? 'Owner',
          userRole: actor?.roleName ?? 'Owner',
          actionType: StaffActionType.memberInvited,
          entityType: 'invitation',
          entityId: invitation.id,
          entityLabel: contact,
          description: 'Invited $contact as $roleName',
        ),
      );

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _InviteShareSheet(
          inviteCode: invitation.inviteCode,
          invitationId: invitation.id,
          businessName: business.business.name,
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = TeamException.fromObject(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(teamRolesProvider).asData?.value ??
        SystemRoles.buildDefaults(ref.watch(teamBusinessIdProvider) ?? '');

    return TeamBusinessGate(
      requiredPermission: AppPermission.manageStaff,
      child: Scaffold(
        appBar: AppBar(title: const Text('Invite Staff')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              TextField(
                controller: _contactCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email or phone',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _roleId,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ...roles.where((r) => r.isActive && r.id != SystemRoleIds.owner).map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(r.name),
                        ),
                      ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _roleId = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _expiryDays,
                decoration: const InputDecoration(
                  labelText: 'Invitation expires',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 day')),
                  DropdownMenuItem(value: 3, child: Text('3 days')),
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 14, child: Text('14 days')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _expiryDays = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _messageCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Permission preview',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text('${_previewPermissions.length} permissions for this role'),
              const SizedBox(height: AppSpacing.sm),
              PermissionSwitchList(
                selected: _previewPermissions,
                onChanged: (_) {},
                readOnly: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create invitation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteShareSheet extends StatelessWidget {
  const _InviteShareSheet({
    required this.inviteCode,
    required this.invitationId,
    required this.businessName,
  });

  final String inviteCode;
  final String invitationId;
  final String businessName;

  String get _link => 'https://app.sabibom.com/invite/$invitationId';

  @override
  Widget build(BuildContext context) {
    final text =
        'You are invited to join $businessName on SabiBom.\n'
        'Open: $_link\n'
        'Or enter code: $inviteCode';
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Invitation ready',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Share the link or code. Email is not sent automatically.',
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText('Code: $inviteCode'),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(_link),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invitation copied')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy invitation'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: text),
            ),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }
}
