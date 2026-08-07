import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../notifications/data/notifications_repository.dart';
import '../application/team_providers.dart';
import '../domain/staff_activity.dart';
import '../domain/staff_invitation.dart';
import '../domain/team_exception.dart';
import 'team_widgets.dart';

class AcceptInvitationScreen extends ConsumerStatefulWidget {
  const AcceptInvitationScreen({
    super.key,
    this.invitationId,
  });

  final String? invitationId;

  @override
  ConsumerState<AcceptInvitationScreen> createState() =>
      _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState
    extends ConsumerState<AcceptInvitationScreen> {
  final _codeCtrl = TextEditingController();
  StaffInvitation? _invitation;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.invitationId != null && widget.invitationId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadById());
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadById() async {
    // Invitation path is under a business — try collection group by scanning
    // via code isn't available; load requires businessId. Use invitationId
    // lookup via collection group on document id is not supported.
    // For deep links we store invitationId and look up via code entry OR
    // we query collectionGroup where id field matches.
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(teamRepositoryProvider);
      final snap = await repo.findInvitationByDocumentId(widget.invitationId!);
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _error = 'Invitation not found.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _invitation = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TeamException.fromObject(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _loadByCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invitation = await ref
          .read(teamRepositoryProvider)
          .findInvitationByCode(_codeCtrl.text);
      if (!mounted) return;
      if (invitation == null) {
        setState(() {
          _error = 'No pending invitation found for that code.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _invitation = invitation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TeamException.fromObject(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    final invitation = _invitation;
    final user = FirebaseAuth.instance.currentUser;
    if (invitation == null || user == null) {
      setState(() => _error = TeamException.unauthenticated.message);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.acceptInvitation(
        invitation: invitation,
        uid: user.uid,
        userEmail: user.email,
        userPhone: user.phoneNumber,
        displayName: user.displayName,
        photoUrl: user.photoURL,
      );
      await repo.logActivity(
        StaffActivity(
          id: '',
          businessId: invitation.businessId,
          userId: user.uid,
          userName: user.displayName ?? user.email ?? 'Staff',
          userRole: invitation.roleName,
          actionType: StaffActionType.invitationAccepted,
          entityType: 'invitation',
          entityId: invitation.id,
          entityLabel: invitation.businessName,
          description: 'Accepted invitation to ${invitation.businessName}',
        ),
      );
      if (invitation.invitedBy.isNotEmpty) {
        await ref.read(notificationsRepositoryProvider).createNotification(
              userId: invitation.invitedBy,
              type: AppNotificationType.invitationAccepted,
              title: 'Invitation accepted',
              body:
                  '${user.displayName ?? user.email ?? 'A staff member'} joined ${invitation.businessName}.',
              businessId: invitation.businessId,
              entityType: 'member',
              entityId: user.uid,
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You joined ${invitation.businessName}'),
        ),
      );
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TeamException.fromObject(e).message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a business')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (user == null) ...[
              const Text('Sign in or create an account to accept an invitation.'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => context.go(AppRoutes.login),
                child: const Text('Sign in'),
              ),
            ] else if (_invitation == null) ...[
              const Text(
                'Enter the invitation code shared with you, or open your invite link.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Invitation code',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _loading ? null : _loadByCode,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ] else ...[
              Text(
                _invitation!.businessName,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Role: ${_invitation!.roleName}'),
              Text(
                'Invited by: ${_invitation!.invitedByName ?? 'Team admin'}',
              ),
              Text(
                'Permissions: ${_invitation!.permissionsSnapshot.length}',
              ),
              if (_invitation!.message != null &&
                  _invitation!.message!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_invitation!.message!),
              ],
              const SizedBox(height: AppSpacing.md),
              PermissionSwitchList(
                selected: _invitation!.permissionsSnapshot,
                onChanged: (_) {},
                readOnly: true,
              ),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _loading || !_invitation!.isAcceptable
                    ? null
                    : _accept,
                child: const Text('Accept invitation'),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Decline'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
