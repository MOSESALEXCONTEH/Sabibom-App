import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../sales/application/sale_void_service.dart';
import '../application/team_providers.dart';
import '../domain/app_permission.dart';
import '../domain/approval_models.dart';
import '../domain/staff_activity.dart';
import '../domain/team_exception.dart';
import 'team_widgets.dart';

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove = ref.watch(canApproveSensitiveActionsProvider);
    final pending = ref.watch(pendingApprovalsProvider);
    final mine = ref.watch(myApprovalRequestsProvider);

    return TeamBusinessGate(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Approvals'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Pending'),
                Tab(text: 'My requests'),
              ],
            ),
            actions: [
              if (ref.watch(
                hasPermissionProvider(AppPermission.editBusinessSettings),
              ))
                IconButton(
                  tooltip: 'Approval settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      context.pushNamed(AppRouteNames.approvalSettings),
                ),
            ],
          ),
          body: TabBarView(
            children: [
              _ApprovalList(
                asyncList: pending,
                emptyLabel: canApprove
                    ? 'No pending approvals.'
                    : 'You cannot approve requests.',
                showActions: canApprove,
              ),
              _ApprovalList(
                asyncList: mine,
                emptyLabel: 'You have no approval requests.',
                showActions: false,
                allowCancelOwn: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalList extends ConsumerWidget {
  const _ApprovalList({
    required this.asyncList,
    required this.emptyLabel,
    required this.showActions,
    this.allowCancelOwn = false,
  });

  final AsyncValue<List<ApprovalRequest>> asyncList;
  final String emptyLabel;
  final bool showActions;
  final bool allowCancelOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncList.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(16), child: AppListSkeleton()),
      error: (_, _) =>
          const AppErrorState(message: 'Could not load approvals.'),
      data: (items) {
        if (items.isEmpty) {
          return AppEmptyState(
            title: 'Nothing here',
            description: emptyLabel,
            icon: Icons.fact_check_outlined,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final a = items[index];
            return Card(
              child: ListTile(
                title: Text(a.type.label),
                subtitle: Text(
                  '${a.requestedByName}\n${a.reason ?? a.entityType}'
                  '\n${formatRelativeTime(a.requestedAt)} · ${a.status.label}',
                ),
                isThreeLine: true,
                onTap: () => context.pushNamed(
                  AppRouteNames.approvalDetails,
                  pathParameters: {'approvalId': a.id},
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ApprovalDetailsScreen extends ConsumerWidget {
  const ApprovalDetailsScreen({super.key, required this.approvalId});

  final String approvalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessId = ref.watch(teamBusinessIdProvider);
    final canApprove = ref.watch(canApproveSensitiveActionsProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return FutureBuilder(
      future: businessId == null
          ? Future<ApprovalRequest?>.value(null)
          : ref
                .read(teamRepositoryProvider)
                .getApproval(businessId: businessId, approvalId: approvalId),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AppListSkeleton(),
            ),
          );
        }
        final a = snap.data;
        if (a == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Approval')),
            body: const AppEmptyState(
              title: 'Not found',
              description: 'Approval not found.',
              icon: Icons.fact_check_outlined,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(a.type.label)),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ListTile(
                title: const Text('Status'),
                trailing: Text(a.status.label),
              ),
              ListTile(
                title: const Text('Requested by'),
                subtitle: Text(
                  '${a.requestedByName} (${a.requestedByRole ?? ''})',
                ),
              ),
              ListTile(
                title: const Text('Record'),
                subtitle: Text('${a.entityType} · ${a.entityId}'),
              ),
              if (a.reason != null)
                ListTile(
                  title: const Text('Reason'),
                  subtitle: Text(a.reason!),
                ),
              if (a.rejectionReason != null)
                ListTile(
                  title: const Text('Rejection reason'),
                  subtitle: Text(a.rejectionReason!),
                ),
              const SizedBox(height: AppSpacing.md),
              if (a.status == ApprovalStatus.pending &&
                  canApprove &&
                  a.requestedBy != uid) ...[
                FilledButton(
                  onPressed: () async {
                    try {
                      final approverName =
                          FirebaseAuth.instance.currentUser?.displayName ??
                          FirebaseAuth.instance.currentUser?.email ??
                          'Approver';
                      // Execute financial action first; only then mark approved.
                      if (a.type == ApprovalRequestType.voidSale) {
                        await ref
                            .read(saleVoidServiceProvider)
                            .executeApprovedVoid(
                              approval: a,
                              approvedByUid: uid!,
                              approvedByName: approverName,
                            );
                      }
                      await ref
                          .read(teamRepositoryProvider)
                          .approveRequest(
                            businessId: businessId!,
                            approvalId: a.id,
                            approvedBy: uid!,
                            approvedByName: approverName,
                          );
                      await ref
                          .read(teamRepositoryProvider)
                          .logActivity(
                            StaffActivity(
                              id: '',
                              businessId: businessId,
                              userId: uid,
                              userName: approverName,
                              userRole: 'manager',
                              actionType: StaffActionType.approvalApproved,
                              entityType: 'approval',
                              entityId: a.id,
                              description: 'Approved ${a.type.label}',
                            ),
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Approved')),
                        );
                        context.pop();
                      }
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
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final reason = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reject request'),
                        content: TextField(
                          controller: ctrl,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(ctx, ctrl.text.trim()),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    );
                    if (reason == null || reason.isEmpty) return;
                    try {
                      await ref
                          .read(teamRepositoryProvider)
                          .rejectRequest(
                            businessId: businessId!,
                            approvalId: a.id,
                            rejectedBy: uid!,
                            rejectedByName:
                                FirebaseAuth
                                    .instance
                                    .currentUser
                                    ?.displayName ??
                                'Approver',
                            rejectionReason: reason,
                          );
                      await ref
                          .read(notificationsRepositoryProvider)
                          .createNotification(
                            userId: a.requestedBy,
                            type: AppNotificationType.approvalRejected,
                            title: 'Request rejected',
                            body:
                                'Your ${a.type.label.toLowerCase()} request was rejected: $reason',
                            businessId: businessId,
                            branchId: a.entitySnapshot['branchId'] as String?,
                            entityType: 'approval',
                            entityId: a.id,
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
                  child: const Text('Reject'),
                ),
              ],
              if (a.status == ApprovalStatus.pending && a.requestedBy == uid)
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(teamRepositoryProvider)
                        .cancelApprovalRequest(
                          businessId: businessId!,
                          approvalId: a.id,
                          cancelledBy: uid!,
                        );
                    if (context.mounted) context.pop();
                  },
                  child: const Text('Cancel my request'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ApprovalSettingsScreen extends ConsumerStatefulWidget {
  const ApprovalSettingsScreen({super.key});

  @override
  ConsumerState<ApprovalSettingsScreen> createState() =>
      _ApprovalSettingsScreenState();
}

class _ApprovalSettingsScreenState
    extends ConsumerState<ApprovalSettingsScreen> {
  ApprovalPolicies? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final policiesAsync = ref.watch(approvalPoliciesProvider);
    final businessId = ref.watch(teamBusinessIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return TeamBusinessGate(
      requiredPermission: AppPermission.editBusinessSettings,
      child: policiesAsync.when(
        loading: () => const Scaffold(
          body: Padding(padding: EdgeInsets.all(16), child: AppListSkeleton()),
        ),
        error: (_, _) => const Scaffold(
          body: AppErrorState(message: 'Could not load policies.'),
        ),
        data: (policies) {
          _draft ??= policies;
          final draft = _draft!;
          return Scaffold(
            appBar: AppBar(title: const Text('Approval settings')),
            body: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SwitchListTile(
                  title: const Text('Require approval to void sales'),
                  value: draft.requireSaleVoidApproval,
                  onChanged: (v) => setState(
                    () => _draft = draft.copyWith(requireSaleVoidApproval: v),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Require approval to void expenses'),
                  value: draft.requireExpenseVoidApproval,
                  onChanged: (v) => setState(
                    () =>
                        _draft = draft.copyWith(requireExpenseVoidApproval: v),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Require approval for price overrides'),
                  value: draft.requirePriceOverrideApproval,
                  onChanged: (v) => setState(
                    () => _draft = draft.copyWith(
                      requirePriceOverrideApproval: v,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Require approval for stock corrections'),
                  value: draft.requireStockCorrectionApproval,
                  onChanged: (v) => setState(
                    () => _draft = draft.copyWith(
                      requireStockCorrectionApproval: v,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text(
                    'Require approval for customer balance adjustments',
                  ),
                  value: draft.customerBalanceAdjustmentApproval,
                  onChanged: (v) => setState(
                    () => _draft = draft.copyWith(
                      customerBalanceAdjustmentApproval: v,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text(
                    'Require approval for supplier overpayments',
                  ),
                  value: draft.supplierOverpaymentApproval,
                  onChanged: (v) => setState(
                    () =>
                        _draft = draft.copyWith(supplierOverpaymentApproval: v),
                  ),
                ),
                ListTile(
                  title: const Text('Discount approval threshold (%)'),
                  subtitle: Text(
                    '${draft.discountApprovalThresholdPercentage.toStringAsFixed(0)}%',
                  ),
                ),
                Slider(
                  value: draft.discountApprovalThresholdPercentage
                      .clamp(0, 100)
                      .toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label:
                      '${draft.discountApprovalThresholdPercentage.toStringAsFixed(0)}%',
                  onChanged: (v) => setState(
                    () => _draft = draft.copyWith(
                      discountApprovalThresholdPercentage: v,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          try {
                            await ref
                                .read(teamRepositoryProvider)
                                .saveApprovalPolicies(
                                  businessId: businessId!,
                                  policies: draft.copyWith(updatedBy: uid),
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  child: const Text('Save policies'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
