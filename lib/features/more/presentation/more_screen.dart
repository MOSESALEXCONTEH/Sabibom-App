import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../business_setup/application/business_experience_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManageStaff = ref.watch(
      hasPermissionProvider(AppPermission.manageStaff),
    );
    final canManageRoles = ref.watch(
      hasPermissionProvider(AppPermission.manageRoles),
    );
    final canAssignBranches = ref.watch(
      hasPermissionProvider(AppPermission.assignStaffToBranches),
    );
    final canViewActivity = ref.watch(
      hasPermissionProvider(AppPermission.viewStaffActivity),
    );
    final canApprove = ref.watch(
      hasPermissionProvider(AppPermission.approveSensitiveActions),
    );
    final canEditSettings = ref.watch(
      hasPermissionProvider(AppPermission.editBusinessSettings),
    );
    final canViewProfit = ref.watch(
      hasPermissionProvider(AppPermission.viewProfit),
    );
    final isOwner = ref.watch(
      currentBusinessMembershipProvider.select(
        (async) => async.asData?.value?.isOwner == true,
      ),
    );
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    final business = activeBusiness is ActiveBusinessData
        ? activeBusiness.business
        : null;
    final showTeam = canManageStaff || canAssignBranches || isOwner;
    final capabilities = ref.watch(currentBusinessCapabilitiesProvider);
    final businessItems = <_MoreItem>[
      _MoreItem(
        Icons.storefront_outlined,
        'Business Profile',
        () => context.push(AppRoutes.businessProfile),
      ),
      _MoreItem(
        Icons.receipt_long_outlined,
        'Receipt Settings',
        () => context.pushNamed(AppRouteNames.settingsReceipt),
      ),
      _MoreItem(
        Icons.account_balance_outlined,
        'Tax and Currency',
        () => context.pushNamed(AppRouteNames.settingsTax),
      ),
      if (showTeam)
        _MoreItem(
          Icons.groups_outlined,
          'Team and Permissions',
          () => context.pushNamed(AppRouteNames.team),
        ),
      if (canManageRoles || isOwner)
        _MoreItem(
          Icons.badge_outlined,
          'Roles',
          () => context.pushNamed(AppRouteNames.teamRoles),
        ),
      if (canViewActivity || isOwner)
        _MoreItem(
          Icons.history,
          'Staff Activity',
          () => context.pushNamed(AppRouteNames.teamActivity),
        ),
      if (canEditSettings || isOwner)
        _MoreItem(
          Icons.rule_folder_outlined,
          'Approval Settings',
          () => context.pushNamed(AppRouteNames.approvalSettings),
        ),
    ];

    final operationsItems = <_MoreItem>[
      if (canApprove || isOwner)
        _MoreItem(
          Icons.fact_check_outlined,
          'Pending Approvals',
          () => context.pushNamed(AppRouteNames.approvals),
        ),
      _MoreItem(
        Icons.payments_outlined,
        'Expenses',
        () => context.pushNamed(AppRouteNames.expenses),
      ),
      if (capabilities.managesPurchases) ...<_MoreItem>[
        _MoreItem(
          Icons.local_shipping_outlined,
          'Suppliers',
          () => context.pushNamed(AppRouteNames.suppliers),
        ),
        _MoreItem(
          Icons.shopping_cart_outlined,
          'Purchases',
          () => context.pushNamed(AppRouteNames.purchases),
        ),
      ],
      _MoreItem(
        Icons.category_outlined,
        'Expense Categories',
        () => context.pushNamed(AppRouteNames.expenseCategories),
      ),
      _MoreItem(
        Icons.print_outlined,
        'Printer Settings',
        () => context.pushNamed(AppRouteNames.settingsPrinter),
      ),
      if (capabilities.managesInventory) ...<_MoreItem>[
        _MoreItem(
          Icons.category_outlined,
          'Categories',
          () => context.pushNamed(AppRouteNames.settingsCategories),
        ),
        _MoreItem(
          Icons.straighten_outlined,
          'Units',
          () => context.pushNamed(AppRouteNames.settingsUnits),
        ),
        _MoreItem(
          Icons.inventory_outlined,
          'Inventory Settings',
          () => context.pushNamed(AppRouteNames.settingsInventory),
        ),
      ],
    ];

    final reportsItems = <_MoreItem>[
      _MoreItem(
        Icons.monitor_heart_outlined,
        'Business Health AI Score',
        () => context.pushNamed(AppRouteNames.businessHealth),
      ),
      _MoreItem(
        Icons.bar_chart_outlined,
        'Business Reports',
        () => context.pushNamed(AppRouteNames.reports),
      ),
      _MoreItem(
        Icons.nightlight_round,
        'End of Day',
        () => context.pushNamed(
          AppRouteNames.endOfDay,
          pathParameters: {
            'dateKey': DateTime.now().toIso8601String().substring(0, 10),
          },
        ),
      ),
      if (canViewProfit || isOwner)
        _MoreItem(
          Icons.trending_up,
          'Profit and Loss',
          () => context.pushNamed(AppRouteNames.reportProfitLoss),
        ),
      if (canEditSettings || isOwner)
        _MoreItem(
          Icons.backup_outlined,
          'Backup and Restore',
          () => context.pushNamed(AppRouteNames.backup),
        ),
    ];

    final accountItems = <_MoreItem>[
      _MoreItem(
        Icons.person_outline,
        'Profile',
        () => context.pushNamed(AppRouteNames.settingsProfile),
      ),
      _MoreItem(
        Icons.badge_outlined,
        'My Role',
        () => context.pushNamed(AppRouteNames.myRole),
      ),
      _MoreItem(
        Icons.lock_outline,
        'Security',
        () => context.pushNamed(AppRouteNames.settingsSecurity),
      ),
      _MoreItem(
        Icons.notifications_outlined,
        'Notifications',
        () => context.pushNamed(AppRouteNames.settingsNotifications),
      ),
      if (isOwner)
        _MoreItem(
          Icons.workspace_premium_outlined,
          'Plans & Billing',
          () => context.pushNamed(AppRouteNames.billing),
        ),
      _MoreItem(
        Icons.mail_outline,
        'Enter invite code',
        () => context.pushNamed(AppRouteNames.invite),
      ),
    ];

    final supportItems = <_MoreItem>[
      _MoreItem(
        Icons.support_agent_outlined,
        'Help and Feedback',
        () => context.pushNamed(AppRouteNames.help),
      ),
      _MoreItem(
        Icons.info_outline,
        'About SabiBom',
        () => context.pushNamed(AppRouteNames.about),
      ),
      if (isOwner)
        _MoreItem(
          Icons.verified_outlined,
          'Release readiness',
          () => context.pushNamed(AppRouteNames.releaseReadiness),
        ),
      _MoreItem(
        Icons.privacy_tip_outlined,
        'Privacy Policy',
        () => context.push(AppRoutes.privacy),
      ),
      _MoreItem(
        Icons.description_outlined,
        'Terms',
        () => context.push(AppRoutes.terms),
      ),
    ];

    return AppTabPageScaffold(
      title: 'More',
      subtitle: 'Settings, ops and account',
      trailing: _BusinessAvatar(
        logoUrl: business?.logoUrl,
        logoCid: business?.logoCid,
        businessName: business?.name,
        onTap: () => context.push(AppRoutes.businessProfile),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppTabChrome.bottomInset,
        ),
        children: <Widget>[
          _MoreSection(title: 'Business', items: businessItems),
          const SizedBox(height: AppSpacing.md),
          _MoreSection(title: 'Operations', items: operationsItems),
          const SizedBox(height: AppSpacing.md),
          _MoreSection(title: 'Reports', items: reportsItems),
          const SizedBox(height: AppSpacing.md),
          _MoreSection(title: 'Account', items: accountItems),
          const SizedBox(height: AppSpacing.md),
          _MoreSection(title: 'Support', items: supportItems),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            onPressed: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again at any time.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) context.go(AppRoutes.onboarding);
  }
}

class _BusinessAvatar extends StatelessWidget {
  const _BusinessAvatar({
    required this.onTap,
    this.logoUrl,
    this.logoCid,
    this.businessName,
  });

  final VoidCallback onTap;
  final String? logoUrl;
  final String? logoCid;
  final String? businessName;

  @override
  Widget build(BuildContext context) {
    final hasLogo =
        logoUrl?.trim().isNotEmpty == true ||
        logoCid?.trim().isNotEmpty == true;
    final name = businessName?.trim() ?? '';
    final initial = name.isEmpty ? 'B' : name.characters.first.toUpperCase();

    return Tooltip(
      message: 'Open business profile',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: ClipOval(
            child: hasLogo
                ? AppNetworkImage(
                    url: logoUrl ?? '',
                    cid: logoCid,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(22),
                    fallbackIcon: Icons.storefront_outlined,
                  )
                : ColoredBox(
                    color: context.brandTint,
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.icon, this.title, this.onTap);
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  String get subtitle => switch (title) {
    'Business Profile' => 'View and update business details',
    'Receipt Settings' => 'Customize receipts and numbering',
    'Tax and Currency' => 'Manage tax rates and currency',
    'Team and Permissions' => 'Manage your team and access',
    'Roles' => 'Create and manage user roles',
    'Staff Activity' => 'Review staff actions and changes',
    'Approval Settings' => 'Configure approval workflows',
    'Pending Approvals' => 'Review and approve requests',
    'Expenses' => 'Track and manage expenses',
    'Suppliers' => 'Manage supplier records',
    'Purchases' => 'View and manage purchases',
    'Expense Categories' => 'Organize expense records',
    'Printer Settings' => 'Configure printer preferences',
    'Categories' => 'Manage product categories',
    'Units' => 'Manage product units',
    'Inventory Settings' => 'Configure inventory preferences',
    'Business Reports' => 'Review business performance',
    'End of Day' => 'Close and review today\'s activity',
    'Profit and Loss' => 'Track income, costs and profit',
    'Backup and Restore' => 'Protect and restore business data',
    'Profile' => 'Manage your personal details',
    'My Role' => 'Review your access and permissions',
    'Security' => 'Manage password and account security',
    'Notifications' => 'Choose alerts and reminders',
    'Enter invite code' => 'Join a business or branch',
    'Help and Feedback' => 'Get support or share feedback',
    'About SabiBom' => 'App information and version',
    'Release readiness' => 'Review production readiness checks',
    'Privacy Policy' => 'Learn how your data is handled',
    'Terms' => 'Review terms of use',
    _ => '',
  };
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.title, required this.items});

  final String title;
  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSectionHeader(title),
        AppSectionCard(
          children: <Widget>[
            for (var i = 0; i < items.length; i++) ...<Widget>[
              ListTile(
                leading: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.brandTint,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      items[i].icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                title: Text(
                  items[i].title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: items[i].subtitle.isEmpty
                    ? null
                    : Text(
                        items[i].subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.mutedTextColor,
                ),
                onTap: items[i].onTap,
              ),
              if (i < items.length - 1)
                Divider(height: 1, indent: 72, color: context.borderColor),
            ],
          ],
        ),
      ],
    );
  }
}
