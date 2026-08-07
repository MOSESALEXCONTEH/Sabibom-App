import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/business_membership.dart';
import '../domain/system_roles.dart';
import 'team_widgets.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  String _search = '';
  MemberStatus? _statusFilter;
  String? _roleFilter;

  @override
  Widget build(BuildContext context) {
    final canManageStaff = ref.watch(
      hasPermissionProvider(AppPermission.manageStaff),
    );
    final canViewActivity = ref.watch(
      hasPermissionProvider(AppPermission.viewStaffActivity),
    );
    final canManageRoles = ref.watch(
      hasPermissionProvider(AppPermission.manageRoles),
    );
    return TeamBusinessGate(
      requiredAnyPermissions: const {
        AppPermission.manageStaff,
        AppPermission.assignStaffToBranches,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team'),
          actions: [
            if (canViewActivity)
              IconButton(
                tooltip: 'Staff activity',
                onPressed: () => context.pushNamed(AppRouteNames.teamActivity),
                icon: const Icon(Icons.history),
              ),
            if (canManageRoles)
              IconButton(
                tooltip: 'Roles',
                onPressed: () => context.pushNamed(AppRouteNames.teamRoles),
                icon: const Icon(Icons.badge_outlined),
              ),
          ],
        ),
        floatingActionButton: canManageStaff
            ? FloatingActionButton.extended(
                onPressed: () => context.pushNamed(AppRouteNames.teamInvite),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Invite Staff'),
              )
            : null,
        body: _TeamBody(
          search: _search,
          statusFilter: _statusFilter,
          roleFilter: _roleFilter,
          onSearch: (v) => setState(() => _search = v),
          onStatus: (v) => setState(() => _statusFilter = v),
          onRole: (v) => setState(() => _roleFilter = v),
        ),
      ),
    );
  }
}

class _TeamBody extends ConsumerWidget {
  const _TeamBody({
    required this.search,
    required this.statusFilter,
    required this.roleFilter,
    required this.onSearch,
    required this.onStatus,
    required this.onRole,
  });

  final String search;
  final MemberStatus? statusFilter;
  final String? roleFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<MemberStatus?> onStatus;
  final ValueChanged<String?> onRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(teamMembersProvider);
    final invitationsAsync = ref.watch(teamInvitationsProvider);

    return membersAsync.when(
      loading: () =>
          const AppListSkeleton(padding: EdgeInsets.all(AppSpacing.md)),
      error: (e, _) => AppErrorState(
        message: 'Could not load team.',
        onRetry: () => ref.invalidate(teamMembersProvider),
      ),
      data: (members) {
        final pendingInvites =
            invitationsAsync.asData?.value
                .where((i) => i.status.name == 'pending')
                .length ??
            0;
        final active = members
            .where((m) => m.status == MemberStatus.active)
            .length;
        final disabled = members
            .where((m) => m.status == MemberStatus.disabled)
            .length;
        final invited =
            members.where((m) => m.status == MemberStatus.invited).length +
            pendingInvites;

        var filtered = members.where((m) {
          if (statusFilter != null && m.status != statusFilter) return false;
          if (roleFilter != null && m.roleId != roleFilter) return false;
          final q = search.trim().toLowerCase();
          if (q.isEmpty) return true;
          return m.effectiveDisplayName.toLowerCase().contains(q) ||
              (m.email?.toLowerCase().contains(q) ?? false) ||
              (m.phone?.contains(q) ?? false) ||
              m.roleName.toLowerCase().contains(q);
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            120,
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(label: 'Total', value: '${members.length}'),
                _StatChip(label: 'Active', value: '$active'),
                _StatChip(label: 'Pending', value: '$invited'),
                _StatChip(label: 'Disabled', value: '$disabled'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search staff',
                border: OutlineInputBorder(),
              ),
              onChanged: onSearch,
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: statusFilter == null,
                    onSelected: (_) => onStatus(null),
                  ),
                  const SizedBox(width: 6),
                  ...MemberStatus.values.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(s.label),
                        selected: statusFilter == s,
                        onSelected: (_) =>
                            onStatus(statusFilter == s ? null : s),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All roles'),
                    selected: roleFilter == null,
                    onSelected: (_) => onRole(null),
                  ),
                  const SizedBox(width: 6),
                  ...[...SystemRoleIds.all, SystemRoleIds.custom].map(
                    (id) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(SystemRoles.labelFor(id)),
                        selected: roleFilter == id,
                        onSelected: (_) => onRole(roleFilter == id ? null : id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (filtered.isEmpty)
              AppEmptyState(
                title: members.isEmpty ? 'No staff members yet' : 'No matches',
                description: members.isEmpty
                    ? 'Invite staff and control what they can access in your business.'
                    : 'No staff match your search or filters.',
                icon: Icons.groups_outlined,
                actionLabel: members.isEmpty ? 'Invite Staff' : null,
                onAction: members.isEmpty
                    ? () => context.pushNamed(AppRouteNames.teamInvite)
                    : null,
              )
            else
              ...filtered.map(
                (m) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      foregroundColor: AppColors.primary,
                      backgroundImage:
                          m.photoUrl != null && m.photoUrl!.isNotEmpty
                          ? NetworkImage(m.photoUrl!)
                          : null,
                      child: m.photoUrl == null || m.photoUrl!.isEmpty
                          ? Text(initialsFor(m.effectiveDisplayName))
                          : null,
                    ),
                    title: Text(m.effectiveDisplayName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.email ?? m.phone ?? 'No contact'),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            RoleBadge(roleId: m.roleId, roleName: m.roleName),
                            StatusBadge(status: m.status),
                          ],
                        ),
                        Text(
                          'Last active: ${formatRelativeTime(m.lastActiveAt ?? m.joinedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${m.effectivePermissions.length} permissions',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => context.pushNamed(
                      AppRouteNames.teamMember,
                      pathParameters: {'uid': m.uid},
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
    );
  }
}
