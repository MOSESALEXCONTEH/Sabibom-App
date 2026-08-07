import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/staff_activity.dart';
import '../domain/system_roles.dart';
import '../domain/team_exception.dart';
import 'team_widgets.dart';

class TeamRolesScreen extends ConsumerWidget {
  const TeamRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(teamRolesProvider);
    return TeamBusinessGate(
      requiredPermission: AppPermission.manageRoles,
      child: Scaffold(
        appBar: AppBar(title: const Text('Roles')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.pushNamed(AppRouteNames.teamRoleNew),
          icon: const Icon(Icons.add),
          label: const Text('Custom role'),
        ),
        body: rolesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: AppListSkeleton(),
          ),
          error: (_, _) =>
              const AppErrorState(message: 'Could not load roles.'),
          data: (roles) {
            if (roles.isEmpty) {
              return const AppEmptyState(
                title: 'No roles yet',
                description: 'Create a custom role or use the built-in ones.',
                icon: Icons.badge_outlined,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                100,
              ),
              itemCount: roles.length,
              itemBuilder: (context, index) {
                final role = roles[index];
                return Card(
                  child: ListTile(
                    title: Text(role.name),
                    subtitle: Text(
                      '${role.description}\n${role.permissions.length} permissions'
                      '${role.isSystemRole ? ' · Built-in' : ''}'
                      '${role.isActive ? '' : ' · Disabled'}',
                    ),
                    isThreeLine: true,
                    trailing: role.isEditable
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: role.isEditable
                        ? () => context.pushNamed(
                            AppRouteNames.teamRoleEdit,
                            pathParameters: {'roleId': role.id},
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class EditRoleScreen extends ConsumerStatefulWidget {
  const EditRoleScreen({super.key, this.roleId});

  final String? roleId;

  @override
  ConsumerState<EditRoleScreen> createState() => _EditRoleScreenState();
}

class _EditRoleScreenState extends ConsumerState<EditRoleScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Set<AppPermission> _permissions = {};
  String _search = '';
  bool _loaded = false;
  bool _saving = false;
  String? _cloneFrom;

  bool get isNew => widget.roleId == null || widget.roleId!.isEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _ensureLoaded(List<RoleDefinition> roles) {
    if (_loaded) return;
    if (!isNew) {
      for (final r in roles) {
        if (r.id == widget.roleId) {
          _nameCtrl.text = r.name;
          _descCtrl.text = r.description;
          _permissions = {...r.permissions};
          _loaded = true;
          return;
        }
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a role name.')));
      return;
    }
    final businessId = ref.read(teamBusinessIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (businessId == null || uid == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      if (isNew) {
        await repo.createCustomRole(
          businessId: businessId,
          name: name,
          description: _descCtrl.text.trim(),
          permissions: _permissions,
          createdBy: uid,
        );
        await repo.logActivity(
          StaffActivity(
            id: '',
            businessId: businessId,
            userId: uid,
            userName: 'Admin',
            userRole: 'owner',
            actionType: StaffActionType.customRoleCreated,
            entityType: 'role',
            entityLabel: name,
            description: 'Created custom role $name',
          ),
        );
      } else {
        await repo.updateCustomRole(
          businessId: businessId,
          roleId: widget.roleId!,
          name: name,
          description: _descCtrl.text.trim(),
          permissions: _permissions,
          updatedBy: uid,
        );
        await repo.logActivity(
          StaffActivity(
            id: '',
            businessId: businessId,
            userId: uid,
            userName: 'Admin',
            userRole: 'owner',
            actionType: StaffActionType.customRoleUpdated,
            entityType: 'role',
            entityId: widget.roleId,
            entityLabel: name,
            description: 'Updated custom role $name',
          ),
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TeamException.fromObject(e).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(teamRolesProvider).asData?.value ?? [];
    _ensureLoaded(roles);
    final actor = ref.watch(currentBusinessMembershipProvider).asData?.value;

    return TeamBusinessGate(
      requiredPermission: AppPermission.manageRoles,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'New role' : 'Edit role'),
          actions: [
            if (!isNew)
              IconButton(
                tooltip: 'Disable role',
                icon: const Icon(Icons.block),
                onPressed: () async {
                  try {
                    await ref
                        .read(teamRepositoryProvider)
                        .disableCustomRole(
                          businessId: ref.read(teamBusinessIdProvider)!,
                          roleId: widget.roleId!,
                          updatedBy: FirebaseAuth.instance.currentUser!.uid,
                        );
                    if (context.mounted) context.pop();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(TeamException.fromObject(e).message),
                        ),
                      );
                    }
                  }
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Role name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            if (isNew) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _cloneFrom ?? '',
                decoration: const InputDecoration(
                  labelText: 'Clone from (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  ...roles.map(
                    (r) => DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _cloneFrom = (v == null || v.isEmpty) ? null : v;
                    if (_cloneFrom != null) {
                      for (final r in roles) {
                        if (r.id == _cloneFrom) {
                          _permissions = {...r.permissions};
                          break;
                        }
                      }
                    }
                  });
                },
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search permissions',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            PermissionSwitchList(
              selected: _permissions,
              searchQuery: _search,
              canGrant: (p) =>
                  actor?.isOwner == true || actor?.hasPermission(p) == true,
              onChanged: (next) => setState(() => _permissions = next),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(isNew ? 'Create role' : 'Save role'),
            ),
          ],
        ),
      ),
    );
  }
}

class StaffActivityScreen extends ConsumerStatefulWidget {
  const StaffActivityScreen({super.key});

  @override
  ConsumerState<StaffActivityScreen> createState() =>
      _StaffActivityScreenState();
}

class _StaffActivityScreenState extends ConsumerState<StaffActivityScreen> {
  String? _userId;
  StaffActionType? _actionType;
  _ActivityPeriod _period = _ActivityPeriod.all;
  bool _sensitiveOnly = false;

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(staffActivityProvider);
    final members = ref.watch(teamMembersProvider).asData?.value ?? [];
    final branchSelection = ref.watch(currentBranchProvider).asData?.value;

    return TeamBusinessGate(
      requiredPermission: AppPermission.viewStaffActivity,
      child: Scaffold(
        appBar: AppBar(title: const Text('Staff activity')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: _userId,
                    decoration: const InputDecoration(
                      labelText: 'Staff member',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All staff'),
                      ),
                      ...members.map(
                        (m) => DropdownMenuItem(
                          value: m.uid,
                          child: Text(m.effectiveDisplayName),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _userId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<StaffActionType?>(
                          initialValue: _actionType,
                          decoration: const InputDecoration(
                            labelText: 'Action type',
                          ),
                          items: <DropdownMenuItem<StaffActionType?>>[
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All actions'),
                            ),
                            ...StaffActionType.values.map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(
                                  type.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _actionType = value),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<_ActivityPeriod>(
                          initialValue: _period,
                          decoration: const InputDecoration(labelText: 'Date'),
                          items: _ActivityPeriod.values
                              .map(
                                (period) => DropdownMenuItem(
                                  value: period,
                                  child: Text(period.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) => setState(
                            () => _period = value ?? _ActivityPeriod.all,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    title: const Text('Sensitive actions only'),
                    value: _sensitiveOnly,
                    onChanged: (v) => setState(() => _sensitiveOnly = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: activityAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: AppListSkeleton(),
                ),
                error: (_, _) =>
                    const AppErrorState(message: 'Could not load activity.'),
                data: (items) {
                  var filtered = items;
                  if (_userId != null) {
                    filtered = filtered
                        .where((a) => a.userId == _userId)
                        .toList();
                  }
                  if (_sensitiveOnly) {
                    filtered = filtered
                        .where((a) => a.actionType.isSensitive)
                        .toList();
                  }
                  if (_actionType != null) {
                    filtered = filtered
                        .where((a) => a.actionType == _actionType)
                        .toList();
                  }
                  final cutoff = _period.cutoff;
                  if (cutoff != null) {
                    filtered = filtered
                        .where(
                          (activity) =>
                              activity.createdAt?.isAfter(cutoff) == true,
                        )
                        .toList();
                  }
                  if (branchSelection != null &&
                      !branchSelection.isAllBranchesMode) {
                    final selectedId = branchSelection.selectedBranch.branchId;
                    final isMain = branchSelection.selectedBranch.isMainBranch;
                    filtered = filterStaffActivityForBranch(
                      activities: filtered,
                      selectedBranchId: selectedId,
                      isMainBranch: isMain,
                    );
                  } else if (branchSelection == null) {
                    filtered = const <StaffActivity>[];
                  }
                  if (filtered.isEmpty) {
                    return const AppEmptyState(
                      title: 'No activity yet',
                      description: 'Staff actions will appear here.',
                      icon: Icons.history,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      96,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final a = filtered[index];
                      return ListTile(
                        title: Text(a.actionType.label),
                        subtitle: Text('${a.userName} · ${a.description}'),
                        trailing: Text(formatRelativeTime(a.createdAt)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ActivityPeriod {
  all('All time'),
  today('Today'),
  sevenDays('Last 7 days'),
  thirtyDays('Last 30 days');

  const _ActivityPeriod(this.label);
  final String label;

  DateTime? get cutoff {
    final now = DateTime.now();
    return switch (this) {
      _ActivityPeriod.all => null,
      _ActivityPeriod.today => DateTime(now.year, now.month, now.day),
      _ActivityPeriod.sevenDays => now.subtract(const Duration(days: 7)),
      _ActivityPeriod.thirtyDays => now.subtract(const Duration(days: 30)),
    };
  }
}

class MyRoleScreen extends ConsumerWidget {
  const MyRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentBusinessMembershipProvider);
    final business = ref.watch(activeBusinessProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('My role')),
      body: membership.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AppListSkeleton(),
        ),
        error: (_, _) => const AccessDeniedScreen(),
        data: (m) {
          if (m == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('You are not an active member of a business.'),
            );
          }
          final bizName = business is ActiveBusinessData
              ? business.business.name
              : 'Business';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ListTile(title: const Text('Business'), subtitle: Text(bizName)),
              ListTile(
                title: const Text('Role'),
                subtitle: Text(m.roleName),
                trailing: RoleBadge(roleId: m.roleId, roleName: m.roleName),
              ),
              ListTile(
                title: const Text('Status'),
                trailing: StatusBadge(status: m.status),
              ),
              ListTile(
                title: const Text('Joined'),
                subtitle: Text(formatRelativeTime(m.joinedAt)),
              ),
              const Divider(),
              Text(
                'Your permissions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              PermissionSwitchList(
                selected: m.effectivePermissions,
                onChanged: (_) {},
                readOnly: true,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'You cannot edit your own permissions. Contact the business owner or manager to request additional access.',
              ),
            ],
          );
        },
      ),
    );
  }
}
