import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../team/application/team_providers.dart';
import '../data/notifications_repository.dart';
import 'notification_navigation.dart';

List<AppNotification> _forCurrentBranch(
  Iterable<AppNotification> notifications, {
  required String? businessId,
  required BranchSelection? selection,
}) {
  return notifications
      .where((notification) {
        final notificationBusinessId = notification.businessId?.trim();
        if (notificationBusinessId == null || notificationBusinessId.isEmpty) {
          return true;
        }
        if (businessId == null || notificationBusinessId != businessId) {
          return false;
        }
        return notificationMatchesBranch(
          notification,
          selectedBranchId: selection?.branchId,
          mainBranchId: selection?.mainBranch.branchId,
          isAllBranches: selection?.isAllBranchesMode == true,
        );
      })
      .toList(growable: false);
}

final branchUnreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications =
      ref.watch(currentUserNotificationsProvider).asData?.value ??
      const <AppNotification>[];
  final businessId = ref.watch(teamBusinessIdProvider);
  final selection = ref.watch(currentBranchProvider).asData?.value;
  return _forCurrentBranch(
    notifications,
    businessId: businessId,
    selection: selection,
  ).where((notification) => notification.isUnread).length;
});

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationStatus? _statusFilter;
  NotificationCategory? _categoryFilter;
  NotificationPriority? _priorityFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(currentUserNotificationsProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final businessId = ref.watch(teamBusinessIdProvider);
    final branchSelection = ref.watch(currentBranchProvider).asData?.value;
    final visibleItems = _forCurrentBranch(
      async.asData?.value ?? const <AppNotification>[],
      businessId: businessId,
      selection: branchSelection,
    );
    final unread = ref.watch(branchUnreadNotificationsCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () =>
                context.pushNamed(AppRouteNames.settingsNotifications),
            icon: const Icon(Icons.tune),
          ),
          if (uid != null)
            TextButton(
              onPressed: () => ref
                  .read(notificationsRepositoryProvider)
                  .markManyRead(
                    uid,
                    visibleItems.where((n) => n.isUnread).map((n) => n.id),
                  ),
              child: const Text('Mark all read'),
            ),
          if (uid != null && _statusFilter == NotificationStatus.archived)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete archived?'),
                    content: const Text(
                      'Permanently remove archived notifications from this device account.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                final count = await ref
                    .read(notificationsRepositoryProvider)
                    .deleteMany(
                      uid,
                      visibleItems.where((n) => n.isArchived).map((n) => n.id),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        count == 0
                            ? 'No archived notifications to delete.'
                            : 'Deleted $count archived notification${count == 1 ? '' : 's'}.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Delete archived'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                Text(
                  unread == 0 ? 'You’re all caught up' : '$unread unread',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _chip(
                  label: 'All',
                  selected: _statusFilter == null,
                  onTap: () => setState(() => _statusFilter = null),
                ),
                _chip(
                  label: 'Unread',
                  selected: _statusFilter == NotificationStatus.unread,
                  onTap: () =>
                      setState(() => _statusFilter = NotificationStatus.unread),
                ),
                _chip(
                  label: 'Read',
                  selected: _statusFilter == NotificationStatus.read,
                  onTap: () =>
                      setState(() => _statusFilter = NotificationStatus.read),
                ),
                _chip(
                  label: 'Archived',
                  selected: _statusFilter == NotificationStatus.archived,
                  onTap: () => setState(
                    () => _statusFilter = NotificationStatus.archived,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _chip(
                  label: 'All categories',
                  selected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                ...NotificationCategory.values.map(
                  (c) => _chip(
                    label: c.title,
                    selected: _categoryFilter == c,
                    onTap: () => setState(
                      () => _categoryFilter = _categoryFilter == c ? null : c,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  const Center(child: Text('Could not load notifications.')),
              data: (items) {
                var filtered = _forCurrentBranch(
                  items,
                  businessId: businessId,
                  selection: branchSelection,
                );
                if (_statusFilter != null) {
                  filtered = filtered
                      .where((n) => n.status == _statusFilter)
                      .toList();
                }
                if (_categoryFilter != null) {
                  filtered = filtered
                      .where((n) => n.category == _categoryFilter)
                      .toList();
                }
                if (_priorityFilter != null) {
                  filtered = filtered
                      .where((n) => n.priority == _priorityFilter)
                      .toList();
                }
                if (filtered.isEmpty) {
                  return _EmptyState(status: _statusFilter);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    96,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = filtered[index];
                    return _NotificationCard(
                      notification: n,
                      onOpen: () => _open(n),
                      onArchive: uid == null
                          ? null
                          : () => ref
                                .read(notificationsRepositoryProvider)
                                .archive(uid, n.id),
                      onToggleRead: uid == null
                          ? null
                          : () {
                              final repo = ref.read(
                                notificationsRepositoryProvider,
                              );
                              if (n.isUnread) {
                                repo.markRead(uid, n.id);
                              } else {
                                repo.markUnread(uid, n.id);
                              }
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(AppNotification n) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && n.isUnread) {
      await ref.read(notificationsRepositoryProvider).markRead(uid, n.id);
    }
    if (!mounted) return;
    await openNotificationRoute(context, n);
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.status});

  final NotificationStatus? status;

  @override
  Widget build(BuildContext context) {
    final title = switch (status) {
      NotificationStatus.unread => 'No unread notifications',
      NotificationStatus.archived => 'No archived notifications',
      _ => 'You’re all caught up',
    };
    final body = switch (status) {
      NotificationStatus.unread =>
        'You have reviewed all current notifications.',
      NotificationStatus.archived =>
        'Notifications you archive will appear here.',
      _ => 'Important business alerts and summaries will appear here.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onOpen,
    this.onArchive,
    this.onToggleRead,
  });

  final AppNotification notification;
  final VoidCallback onOpen;
  final VoidCallback? onArchive;
  final VoidCallback? onToggleRead;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final time = n.createdAt == null
        ? ''
        : DateFormat('d MMM · HH:mm').format(n.createdAt!);
    final icon = switch (n.category) {
      NotificationCategory.inventory => Icons.inventory_2_outlined,
      NotificationCategory.expiry => Icons.event_busy_outlined,
      NotificationCategory.expiredStock => Icons.delete_forever_outlined,
      NotificationCategory.customers => Icons.people_outline,
      NotificationCategory.suppliers => Icons.local_shipping_outlined,
      NotificationCategory.approvals => Icons.fact_check_outlined,
      NotificationCategory.endOfDay => Icons.nightlight_round,
      NotificationCategory.reports => Icons.bar_chart_outlined,
      NotificationCategory.staff => Icons.badge_outlined,
      NotificationCategory.expenses => Icons.payments_outlined,
      NotificationCategory.sales => Icons.point_of_sale_outlined,
      NotificationCategory.security => Icons.security,
      NotificationCategory.system => Icons.info_outline,
    };

    return Card(
      color: n.isUnread
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: const Color(0xFF5B3DF5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (n.isUnread)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: Color(0xFF5B3DF5),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          n.priority.label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(n.message),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (n.businessName != null &&
                            n.businessName!.isNotEmpty)
                          n.businessName!,
                        n.category.title,
                        time,
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (n.actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        n.actionLabel!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'read') onToggleRead?.call();
                  if (value == 'archive') onArchive?.call();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'read',
                    child: Text(n.isUnread ? 'Mark read' : 'Mark unread'),
                  ),
                  const PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
