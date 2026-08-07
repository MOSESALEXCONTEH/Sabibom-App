import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../branches/domain/business_branch.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/business_membership.dart';
import '../domain/staff_activity.dart';
import '../domain/system_roles.dart';
import '../domain/team_exception.dart';
import 'team_widgets.dart';

class StaffDetailsScreen extends ConsumerWidget {
  const StaffDetailsScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TeamBusinessGate(
      requiredAnyPermissions: const {
        AppPermission.manageStaff,
        AppPermission.assignStaffToBranches,
      },
      child: _StaffDetailsBody(uid: uid),
    );
  }
}

class _StaffDetailsBody extends ConsumerWidget {
  const _StaffDetailsBody({required this.uid});

  final String uid;

  String _branchAccessSummary(
    BusinessMembership member,
    List<BusinessBranch> branches,
  ) {
    final names = branches
        .where((branch) => member.assignedBranchIds.contains(branch.branchId))
        .map((branch) => branch.name)
        .toList(growable: false);
    if (names.isEmpty) return 'Assign at least one active branch.';
    final defaultName = branches
        .where((branch) => branch.branchId == member.defaultBranchId)
        .map((branch) => branch.name)
        .firstOrNull;
    return defaultName == null
        ? names.join(', ')
        : '${names.join(', ')}. Default: $defaultName';
  }

  Future<void> _editBranchAccess({
    required BuildContext context,
    required WidgetRef ref,
    required BusinessMembership member,
    required List<BusinessBranch> branches,
    required String businessId,
    required BusinessMembership actor,
    required String updatedBy,
  }) async {
    final activeBranches = branches
        .where((branch) => branch.isSelectable)
        .toList(growable: false);
    final selected = member.assignedBranchIds
        .where(activeBranches.map((branch) => branch.branchId).toSet().contains)
        .toSet();
    String? defaultBranchId = selected.contains(member.defaultBranchId)
        ? member.defaultBranchId
        : selected.firstOrNull;

    final draft = await showDialog<_BranchAccessDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Assign branches'),
            content: SizedBox(
              width: 420,
              child: activeBranches.isEmpty
                  ? const Text('No active branches are available.')
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final branch in activeBranches)
                            CheckboxListTile(
                              value: selected.contains(branch.branchId),
                              title: Text(branch.name),
                              subtitle: Text(branch.code),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    selected.add(branch.branchId);
                                    defaultBranchId ??= branch.branchId;
                                  } else {
                                    selected.remove(branch.branchId);
                                    if (defaultBranchId == branch.branchId) {
                                      defaultBranchId = selected.firstOrNull;
                                    }
                                  }
                                });
                              },
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          DropdownButtonFormField<String>(
                            initialValue: defaultBranchId,
                            decoration: const InputDecoration(
                              labelText: 'Default branch',
                              border: OutlineInputBorder(),
                            ),
                            items: activeBranches
                                .where(
                                  (branch) =>
                                      selected.contains(branch.branchId),
                                )
                                .map(
                                  (branch) => DropdownMenuItem(
                                    value: branch.branchId,
                                    child: Text(branch.name),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: selected.isEmpty
                                ? null
                                : (value) => setDialogState(
                                    () => defaultBranchId = value,
                                  ),
                          ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty || defaultBranchId == null
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        _BranchAccessDraft(
                          branchIds: Set.unmodifiable(selected),
                          defaultBranchId: defaultBranchId!,
                        ),
                      ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (draft == null) return;

    try {
      await ref
          .read(teamRepositoryProvider)
          .updateMemberBranchAccess(
            businessId: businessId,
            targetUid: member.uid,
            assignedBranchIds: draft.branchIds,
            allBranchesAccess: false,
            defaultBranchId: draft.defaultBranchId,
            updatedBy: updatedBy,
            actor: actor,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated branch access for ${member.effectiveDisplayName}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TeamException.fromObject(error).message)),
        );
      }
    }
  }

  Future<void> _confirmAction({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String body,
    required Future<void> Function(String? reason) onConfirm,
    bool requireReason = false,
  }) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(body),
            if (requireReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onConfirm(
        reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Updated')));
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
    final memberAsync = ref.watch(memberByIdProvider(uid));
    final activityAsync = ref.watch(staffActivityProvider);
    final actor = ref.watch(currentBusinessMembershipProvider).asData?.value;
    final businessId = ref.watch(teamBusinessIdProvider);
    final branches = businessId == null
        ? const <BusinessBranch>[]
        : ref.watch(businessBranchesProvider(businessId)).asData?.value ??
              const <BusinessBranch>[];
    final me = FirebaseAuth.instance.currentUser?.uid;

    return memberAsync.when(
      loading: () => const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: AppListSkeleton()),
      ),
      error: (_, _) => const Scaffold(
        body: AppErrorState(message: 'Could not load staff member.'),
      ),
      data: (member) {
        if (member == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Staff')),
            body: const AppEmptyState(
              title: 'Not found',
              description: 'Staff member not found.',
              icon: Icons.person_off_outlined,
            ),
          );
        }
        final theirActivity = (activityAsync.asData?.value ?? [])
            .where((a) => a.userId == uid)
            .take(10)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(member.effectiveDisplayName),
            actions: [
              if (actor?.hasPermission(AppPermission.viewStaffActivity) == true)
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () =>
                      context.pushNamed(AppRouteNames.teamActivity),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage:
                      member.photoUrl != null && member.photoUrl!.isNotEmpty
                      ? NetworkImage(member.photoUrl!)
                      : null,
                  child: member.photoUrl == null || member.photoUrl!.isEmpty
                      ? Text(
                          initialsFor(member.effectiveDisplayName),
                          style: const TextStyle(fontSize: 28),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                member.effectiveDisplayName,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (member.email != null)
                Text(member.email!, textAlign: TextAlign.center),
              if (member.phone != null)
                Text(member.phone!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  RoleBadge(roleId: member.roleId, roleName: member.roleName),
                  StatusBadge(status: member.status),
                ],
              ),
              ListTile(
                title: const Text('Joined'),
                subtitle: Text(formatRelativeTime(member.joinedAt)),
              ),
              ListTile(
                title: const Text('Last active'),
                subtitle: Text(formatRelativeTime(member.lastActiveAt)),
              ),
              const Divider(),
              Text(
                'Branch access',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(
                  member.isOwner
                      ? 'All active branches'
                      : member.assignedBranchIds.isEmpty
                      ? 'No branch assigned'
                      : '${member.assignedBranchIds.length} assigned',
                ),
                subtitle: Text(
                  member.isOwner
                      ? 'Owner access cannot be restricted.'
                      : _branchAccessSummary(member, branches),
                ),
                trailing:
                    member.uid != me &&
                        !member.isOwner &&
                        (actor?.isOwner == true ||
                            actor?.hasPermission(
                                  AppPermission.assignStaffToBranches,
                                ) ==
                                true)
                    ? IconButton(
                        tooltip: 'Edit branch access',
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        onPressed: () => _editBranchAccess(
                          context: context,
                          ref: ref,
                          member: member,
                          branches: branches,
                          businessId: businessId!,
                          actor: actor!,
                          updatedBy: me!,
                        ),
                      )
                    : null,
              ),
              const Divider(),
              Text(
                'Permissions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              PermissionSwitchList(
                selected: member.effectivePermissions,
                onChanged: (_) {},
                readOnly: true,
              ),
              const Divider(),
              Text(
                'Recent activity',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (theirActivity.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No recent activity.'),
                )
              else
                ...theirActivity.map(
                  (a) => ListTile(
                    title: Text(a.actionType.label),
                    subtitle: Text(a.description),
                    trailing: Text(formatRelativeTime(a.createdAt)),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              if (member.uid != me &&
                  (actor?.isOwner == true ||
                      actor?.hasPermission(AppPermission.manageStaff) ==
                          true)) ...[
                OutlinedButton(
                  onPressed: () => context.pushNamed(
                    AppRouteNames.teamMemberEditRole,
                    pathParameters: {'uid': uid},
                  ),
                  child: const Text('Edit Role'),
                ),
                OutlinedButton(
                  onPressed: () => context.pushNamed(
                    AppRouteNames.teamMemberPermissions,
                    pathParameters: {'uid': uid},
                  ),
                  child: const Text('Edit Permissions'),
                ),
                if (member.status == MemberStatus.active)
                  FilledButton.tonal(
                    onPressed: () => _confirmAction(
                      context: context,
                      ref: ref,
                      title: 'Disable staff',
                      body:
                          'They will lose access to this business. History is kept.',
                      requireReason: true,
                      onConfirm: (reason) async {
                        await ref
                            .read(teamRepositoryProvider)
                            .disableMember(
                              businessId: businessId!,
                              targetUid: uid,
                              disabledBy: me!,
                              reason: reason,
                            );
                        await ref
                            .read(teamRepositoryProvider)
                            .logActivity(
                              StaffActivity(
                                id: '',
                                businessId: businessId,
                                userId: me,
                                userName:
                                    actor?.effectiveDisplayName ?? 'Admin',
                                userRole: actor?.roleName ?? '',
                                actionType: StaffActionType.memberDisabled,
                                entityType: 'member',
                                entityId: uid,
                                entityLabel: member.effectiveDisplayName,
                                description:
                                    'Disabled ${member.effectiveDisplayName}',
                              ),
                            );
                      },
                    ),
                    child: const Text('Disable Staff'),
                  ),
                if (member.status == MemberStatus.disabled)
                  FilledButton(
                    onPressed: () => _confirmAction(
                      context: context,
                      ref: ref,
                      title: 'Restore staff',
                      body: 'They will regain access to this business.',
                      onConfirm: (_) async {
                        await ref
                            .read(teamRepositoryProvider)
                            .restoreMember(
                              businessId: businessId!,
                              targetUid: uid,
                              restoredBy: me!,
                            );
                        await ref
                            .read(teamRepositoryProvider)
                            .logActivity(
                              StaffActivity(
                                id: '',
                                businessId: businessId,
                                userId: me,
                                userName:
                                    actor?.effectiveDisplayName ?? 'Admin',
                                userRole: actor?.roleName ?? '',
                                actionType: StaffActionType.memberRestored,
                                entityType: 'member',
                                entityId: uid,
                                entityLabel: member.effectiveDisplayName,
                                description:
                                    'Restored ${member.effectiveDisplayName}',
                              ),
                            );
                      },
                    ),
                    child: const Text('Restore Staff'),
                  ),
                if (member.status != MemberStatus.removed)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => _confirmAction(
                      context: context,
                      ref: ref,
                      title: 'Remove staff',
                      body:
                          'They will be removed from this business. History is kept.',
                      requireReason: true,
                      onConfirm: (reason) async {
                        await ref
                            .read(teamRepositoryProvider)
                            .removeMember(
                              businessId: businessId!,
                              targetUid: uid,
                              removedBy: me!,
                              reason: reason,
                            );
                        await ref
                            .read(teamRepositoryProvider)
                            .logActivity(
                              StaffActivity(
                                id: '',
                                businessId: businessId,
                                userId: me,
                                userName:
                                    actor?.effectiveDisplayName ?? 'Admin',
                                userRole: actor?.roleName ?? '',
                                actionType: StaffActionType.memberRemoved,
                                entityType: 'member',
                                entityId: uid,
                                entityLabel: member.effectiveDisplayName,
                                description:
                                    'Removed ${member.effectiveDisplayName}',
                              ),
                            );
                        if (context.mounted) context.pop();
                      },
                    ),
                    child: const Text('Remove Staff'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class EditMemberRoleScreen extends ConsumerStatefulWidget {
  const EditMemberRoleScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<EditMemberRoleScreen> createState() =>
      _EditMemberRoleScreenState();
}

class _EditMemberRoleScreenState extends ConsumerState<EditMemberRoleScreen> {
  String? _roleId;
  bool _saving = false;

  Set<AppPermission> _permsFor(String roleId, List<RoleDefinition> roles) {
    for (final r in roles) {
      if (r.id == roleId) return r.permissions;
    }
    return SystemRoles.defaultPermissionsFor(roleId);
  }

  String _nameFor(String roleId, List<RoleDefinition> roles) {
    for (final r in roles) {
      if (r.id == roleId) return r.name;
    }
    return SystemRoles.labelFor(roleId);
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(memberByIdProvider(widget.uid)).asData?.value;
    final roles = ref.watch(teamRolesProvider).asData?.value ?? [];
    final actor = ref.watch(currentBusinessMembershipProvider).asData?.value;
    final businessId = ref.watch(teamBusinessIdProvider);
    final selected = _roleId ?? member?.roleId;

    return TeamBusinessGate(
      requiredPermission: AppPermission.manageStaff,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit role')),
        body: member == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: AppListSkeleton(),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (value) => setState(() => _roleId = value),
                    child: Column(
                      children: roles.where((r) => r.isActive).map((role) {
                        final blockedOwner =
                            role.id == SystemRoleIds.owner &&
                            actor?.isOwner != true;
                        return RadioListTile<String>(
                          value: role.id,
                          title: Text(role.name),
                          subtitle: Text(role.description),
                          enabled: !blockedOwner,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (selected != null)
                    PermissionSwitchList(
                      selected: _permsFor(selected, roles),
                      onChanged: (_) {},
                      readOnly: true,
                    ),
                  FilledButton(
                    onPressed: _saving || selected == null || actor == null
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              final perms = _permsFor(selected, roles);
                              await ref
                                  .read(teamRepositoryProvider)
                                  .updateMemberRole(
                                    businessId: businessId!,
                                    targetUid: widget.uid,
                                    roleId: selected,
                                    roleName: _nameFor(selected, roles),
                                    permissions: perms,
                                    updatedBy:
                                        FirebaseAuth.instance.currentUser!.uid,
                                    actor: actor,
                                  );
                              await ref
                                  .read(teamRepositoryProvider)
                                  .logActivity(
                                    StaffActivity(
                                      id: '',
                                      businessId: businessId,
                                      userId: FirebaseAuth
                                          .instance
                                          .currentUser!
                                          .uid,
                                      userName: actor.effectiveDisplayName,
                                      userRole: actor.roleName,
                                      actionType: StaffActionType.roleChanged,
                                      entityType: 'member',
                                      entityId: widget.uid,
                                      description:
                                          'Changed role to ${_nameFor(selected, roles)}',
                                    ),
                                  );
                              if (context.mounted) context.pop();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      TeamException.fromObject(e).message,
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: const Text('Save role'),
                  ),
                ],
              ),
      ),
    );
  }
}

class EditMemberPermissionsScreen extends ConsumerStatefulWidget {
  const EditMemberPermissionsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<EditMemberPermissionsScreen> createState() =>
      _EditMemberPermissionsScreenState();
}

class _EditMemberPermissionsScreenState
    extends ConsumerState<EditMemberPermissionsScreen> {
  Set<AppPermission>? _selected;
  String _search = '';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(memberByIdProvider(widget.uid)).asData?.value;
    final actor = ref.watch(currentBusinessMembershipProvider).asData?.value;
    final businessId = ref.watch(teamBusinessIdProvider);
    final selected = _selected ?? member?.effectivePermissions ?? {};

    return TeamBusinessGate(
      requiredPermission: AppPermission.manageStaff,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit permissions'),
          actions: [
            TextButton(
              onPressed: member == null
                  ? null
                  : () {
                      setState(() {
                        _selected = SystemRoles.defaultPermissionsFor(
                          member.roleId,
                        );
                      });
                    },
              child: const Text('Reset'),
            ),
          ],
        ),
        body: member == null || actor == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: AppListSkeleton(),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search permissions',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  PermissionSwitchList(
                    selected: selected,
                    searchQuery: _search,
                    canGrant: (p) => actor.isOwner || actor.hasPermission(p),
                    onChanged: (next) => setState(() => _selected = next),
                  ),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              await ref
                                  .read(teamRepositoryProvider)
                                  .updateMemberPermissions(
                                    businessId: businessId!,
                                    targetUid: widget.uid,
                                    permissions: selected,
                                    updatedBy:
                                        FirebaseAuth.instance.currentUser!.uid,
                                    actor: actor,
                                  );
                              await ref
                                  .read(teamRepositoryProvider)
                                  .logActivity(
                                    StaffActivity(
                                      id: '',
                                      businessId: businessId,
                                      userId: FirebaseAuth
                                          .instance
                                          .currentUser!
                                          .uid,
                                      userName: actor.effectiveDisplayName,
                                      userRole: actor.roleName,
                                      actionType:
                                          StaffActionType.permissionsChanged,
                                      entityType: 'member',
                                      entityId: widget.uid,
                                      description:
                                          'Updated permissions for ${member.effectiveDisplayName}',
                                    ),
                                  );
                              if (context.mounted) context.pop();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      TeamException.fromObject(e).message,
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: const Text('Save permissions'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BranchAccessDraft {
  const _BranchAccessDraft({
    required this.branchIds,
    required this.defaultBranchId,
  });

  final Set<String> branchIds;
  final String defaultBranchId;
}
