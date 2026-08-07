import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';

/// Shows who can access this business and what each role can do.
class TeamPermissionsScreen extends ConsumerWidget {
  const TeamPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final businessId = profile?.activeBusinessId;
    if (businessId == null || businessId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No business has been set up yet.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Team and Permissions')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          Text(
            'Control who can sell, manage stock, and change business settings. '
            'Owners and managers can upload the logo and edit the business profile.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('businesses')
                .doc(businessId)
                .snapshots(),
            builder: (context, businessSnap) {
              final ownerId =
                  businessSnap.data?.data()?['ownerId'] as String? ?? '';
              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.verified_user)),
                  title: Text(
                    ownerId == currentUid ? 'You (Owner)' : 'Business owner',
                  ),
                  subtitle: Text(
                    ownerId.isEmpty ? 'Owner account' : 'ID: ${_short(ownerId)}',
                  ),
                  trailing: const Chip(label: Text('Owner')),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Team members',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('businesses')
                .doc(businessId)
                .collection('members')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? const [];
              final members = docs.where((doc) {
                final role = doc.data()['role'] as String? ?? '';
                return role != 'owner';
              }).toList(growable: false);
              if (members.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.groups_outlined),
                    title: Text('No team members yet'),
                    subtitle: Text(
                      'Invite staff when you are ready. Until then, only the '
                      'owner can manage this business.',
                    ),
                  ),
                );
              }
              return Column(
                children: members.map((doc) {
                  final data = doc.data();
                  final role = (data['role'] as String? ?? 'cashier').toLowerCase();
                  final status = data['status'] as String? ?? 'active';
                  final name = data['displayName'] as String? ??
                      data['fullName'] as String? ??
                      'Team member';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      ),
                      title: Text(name),
                      subtitle: Text('${_roleLabel(role)} · $status'),
                      trailing: Text(
                        _roleLabel(role),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Roles',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RoleCard(
            title: 'Owner',
            body:
                'Full access: sales, products, customers, settings, team, and branding.',
          ),
          const _RoleCard(
            title: 'Manager',
            body:
                'Can manage products, customers, sales, and business profile. '
                'Cannot remove the owner.',
          ),
          const _RoleCard(
            title: 'Cashier',
            body:
                'Can record sales and look up customers. Cannot change settings '
                'or business branding.',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Invite team members'),
                  content: const Text(
                    'Team invites will let you add staff by phone or email. '
                    'For now, share device access carefully and keep the owner '
                    'account secure.',
                  ),
                  actions: <Widget>[
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('How inviting works'),
          ),
        ],
      ),
    );
  }

  static String _short(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';

  static String _roleLabel(String role) {
    switch (role) {
      case 'manager':
        return 'Manager';
      case 'owner':
        return 'Owner';
      default:
        return 'Cashier';
    }
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(body),
      ),
    ),
  );
}
