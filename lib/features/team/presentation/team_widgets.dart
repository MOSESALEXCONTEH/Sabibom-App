import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/business_membership.dart';
import '../domain/system_roles.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access restricted')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.xl),
            Icon(
              Icons.lock_outline,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Access restricted',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message ?? 'You do not have permission to open this section.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Contact the business owner or manager.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gates team screens: requires active business + optional permission.
class TeamBusinessGate extends ConsumerWidget {
  const TeamBusinessGate({
    super.key,
    required this.child,
    this.requiredPermission,
    this.requiredAnyPermissions = const {},
  });

  final Widget child;
  final AppPermission? requiredPermission;
  final Set<AppPermission> requiredAnyPermissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessId = ref.watch(teamBusinessIdProvider);
    if (businessId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Set up your business first',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Create or select a business before managing your team.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => context.push(AppRoutes.businessSetup),
                child: const Text('Set Up Business'),
              ),
            ],
          ),
        ),
      );
    }

    if (requiredPermission == null && requiredAnyPermissions.isEmpty) {
      return child;
    }

    final membershipAsync = ref.watch(currentBusinessMembershipProvider);
    final businessState = ref.watch(activeBusinessProvider).asData?.value;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return membershipAsync.when(
      loading: () => const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: AppListSkeleton()),
      ),
      error: (_, _) => const AccessDeniedScreen(),
      data: (membership) {
        final hasRequiredPermission =
            requiredPermission != null &&
            membership?.hasPermission(requiredPermission!) == true;
        final hasAnyRequiredPermission =
            requiredAnyPermissions.isNotEmpty &&
            membership?.hasAnyPermission(requiredAnyPermissions) == true;
        if (hasRequiredPermission || hasAnyRequiredPermission) {
          return child;
        }
        // Legacy owner: business.ownerId matches and membership missing/thin.
        if (businessState is ActiveBusinessData &&
            uid != null &&
            businessState.business.ownerId == uid) {
          return child;
        }
        return const AccessDeniedScreen();
      },
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.roleId, required this.roleName});

  final String roleId;
  final String roleName;

  @override
  Widget build(BuildContext context) {
    final color = switch (roleId) {
      SystemRoleIds.owner => const Color(0xFF5B3DF5),
      SystemRoleIds.manager => const Color(0xFF1565C0),
      SystemRoleIds.cashier => const Color(0xFF2E7D32),
      SystemRoleIds.stockKeeper => const Color(0xFFEF6C00),
      SystemRoleIds.accountant => const Color(0xFF00838F),
      _ => Theme.of(context).colorScheme.secondary,
    };
    return Chip(
      label: Text(roleName.isEmpty ? SystemRoles.labelFor(roleId) : roleName),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final MemberStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MemberStatus.active => Colors.green.shade700,
      MemberStatus.invited => Colors.orange.shade800,
      MemberStatus.disabled => Colors.grey.shade700,
      MemberStatus.removed => Colors.red.shade700,
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(status.label),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class PermissionSwitchList extends StatelessWidget {
  const PermissionSwitchList({
    super.key,
    required this.selected,
    required this.onChanged,
    this.readOnly = false,
    this.canGrant,
    this.searchQuery = '',
  });

  final Set<AppPermission> selected;
  final ValueChanged<Set<AppPermission>> onChanged;
  final bool readOnly;
  final bool Function(AppPermission permission)? canGrant;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final q = searchQuery.trim().toLowerCase();
    return Column(
      children: PermissionGroup.values.map((group) {
        final defs = PermissionRegistry.byGroup(group).where((d) {
          if (q.isEmpty) return true;
          return d.title.toLowerCase().contains(q) ||
              d.code.code.contains(q) ||
              d.description.toLowerCase().contains(q);
        }).toList();
        if (defs.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          title: Text(group.title),
          initiallyExpanded: q.isNotEmpty,
          children: defs.map((def) {
            final enabled = canGrant?.call(def.code) ?? true;
            final locked = def.ownerOnly || (!enabled && !readOnly);
            return SwitchListTile(
              title: Text(def.title),
              subtitle: Text(
                locked && !readOnly
                    ? '${def.description} (You cannot grant this permission.)'
                    : def.description,
              ),
              value: selected.contains(def.code),
              onChanged: readOnly || locked
                  ? null
                  : (value) {
                      final next = {...selected};
                      if (value) {
                        next.add(def.code);
                      } else {
                        next.remove(def.code);
                      }
                      onChanged(next);
                    },
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

String formatRelativeTime(DateTime? value) {
  if (value == null) return 'Never';
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${value.day}/${value.month}/${value.year}';
}

String initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
