import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../application/current_branch_providers.dart';
import '../data/business_branch_repository.dart';
import '../domain/business_branch.dart';

class BusinessBranchesScreen extends ConsumerStatefulWidget {
  const BusinessBranchesScreen({super.key});

  @override
  ConsumerState<BusinessBranchesScreen> createState() =>
      _BusinessBranchesScreenState();
}

class _BusinessBranchesScreenState extends ConsumerState<BusinessBranchesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final businessId = switch (active) {
      ActiveBusinessData(:final business) => business.businessId,
      _ => null,
    };
    if (businessId == null) {
      return const Scaffold(
        body: Center(child: Text('No business has been set up yet.')),
      );
    }

    final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
    final canManage = membership?.hasPermission(AppPermission.manageBranches) == true || membership?.isOwner == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Business Branches')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showBranchDialog(context, businessId),
              icon: const Icon(Icons.add),
              label: const Text('Create Branch'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search branches',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<BusinessBranch>>(
              stream: ref
                  .read(businessBranchRepositoryProvider)
                  .watchBranches(businessId),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? const <BusinessBranch>[];
                final filtered = _filter(branches, _searchController.text);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    branches.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (filtered.isEmpty) {
                  return const Center(child: Text('No branches found.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final branch = filtered[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          branch.isMainBranch
                              ? Icons.star
                              : Icons.storefront_outlined,
                        ),
                        title: Text(branch.name),
                        subtitle: Text(
                          '${branch.code} · ${branch.status.name}${branch.managerUid == null ? '' : ' · manager: ${branch.managerUid}'}',
                        ),
                        trailing: canManage
                            ? PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'details':
                                      _showBranchDetails(context, branch);
                                      break;
                                    case 'edit':
                                      _showBranchDialog(
                                        context,
                                        businessId,
                                        branch: branch,
                                      );
                                      break;
                                    case 'deactivate':
                                      _toggleStatus(
                                        context,
                                        businessId,
                                        branch,
                                        BranchStatus.inactive,
                                      );
                                      break;
                                    case 'activate':
                                      _toggleStatus(
                                        context,
                                        businessId,
                                        branch,
                                        BranchStatus.active,
                                      );
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'details',
                                    child: Text('View details'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit branch'),
                                  ),
                                  if (!branch.isMainBranch && branch.isActive)
                                    const PopupMenuItem(
                                      value: 'deactivate',
                                      child: Text('Deactivate branch'),
                                    ),
                                  if (!branch.isMainBranch && !branch.isActive)
                                    const PopupMenuItem(
                                      value: 'activate',
                                      child: Text('Activate branch'),
                                    ),
                                ],
                              )
                            : null,
                        onTap: () => ref
                            .read(currentBranchProvider.notifier)
                            .selectBranch(branch.branchId),
                      ),
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

  List<BusinessBranch> _filter(List<BusinessBranch> branches, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return branches;
    return branches.where((branch) {
      return branch.name.toLowerCase().contains(needle) ||
          branch.code.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  Future<void> _toggleStatus(
    BuildContext context,
    String businessId,
    BusinessBranch branch,
    BranchStatus status,
  ) async {
    if (branch.isMainBranch && status != BranchStatus.active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Main branch cannot be deactivated.')),
      );
      return;
    }
    try {
      await ref.read(businessBranchRepositoryProvider).setBranchStatus(
            businessId: businessId,
            branchId: branch.branchId,
            status: status,
            updatedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
          );
    } catch (error) {
      if (!context.mounted) return;
      final message = error is BranchException
          ? (error.message ?? 'Could not update branch.')
          : 'Could not update branch: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _showBranchDialog(
    BuildContext context,
    String businessId, {
    BusinessBranch? branch,
  }) async {
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final addressController = TextEditingController(text: branch?.address ?? '');
    final cityController = TextEditingController(text: branch?.city ?? '');
    final countryController = TextEditingController(text: branch?.country ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    final emailController = TextEditingController(text: branch?.email ?? '');
    final managerController = TextEditingController(text: branch?.managerUid ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(branch == null ? 'Create branch' : 'Edit branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Branch name'),
              ),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Branch code'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              TextField(
                controller: countryController,
                decoration: const InputDecoration(labelText: 'Country'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: managerController,
                decoration: const InputDecoration(
                  labelText: 'Manager UID',
                  helperText: 'Must belong to this business.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != true) return;

    final repo = ref.read(businessBranchRepositoryProvider);
    try {
      if (branch == null) {
        await repo.createBranch(
          businessId: businessId,
          name: nameController.text,
          code: codeController.text,
          address: addressController.text,
          city: cityController.text,
          country: countryController.text,
          phone: phoneController.text,
          email: emailController.text,
          managerUid: managerController.text,
          createdBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        );
      } else {
        await repo.updateBranch(
          businessId: businessId,
          branchId: branch.branchId,
          name: nameController.text,
          code: codeController.text,
          address: addressController.text,
          city: cityController.text,
          country: countryController.text,
          phone: phoneController.text,
          email: emailController.text,
          managerUid: managerController.text,
          updatedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      final message = error is BranchException
          ? (error.message ?? 'Could not save branch.')
          : 'Could not save branch: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _showBranchDetails(
    BuildContext context,
    BusinessBranch branch,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(branch.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code: ${branch.code}'),
            Text('Status: ${branch.status.name}'),
            Text('Main branch: ${branch.isMainBranch ? 'Yes' : 'No'}'),
            Text('Manager UID: ${branch.managerUid ?? 'Not assigned'}'),
            if ((branch.address ?? '').isNotEmpty)
              Text('Address: ${branch.address}'),
            if ((branch.city ?? '').isNotEmpty) Text('City: ${branch.city}'),
            if ((branch.country ?? '').isNotEmpty)
              Text('Country: ${branch.country}'),
            if ((branch.phone ?? '').isNotEmpty)
              Text('Phone: ${branch.phone}'),
            if ((branch.email ?? '').isNotEmpty)
              Text('Email: ${branch.email}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
