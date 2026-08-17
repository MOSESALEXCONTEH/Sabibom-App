import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../branches/domain/business_branch.dart';
import '../domain/app_permission.dart';
import '../domain/approval_models.dart';
import '../domain/business_membership.dart';
import '../domain/permission_service.dart';
import '../domain/staff_activity.dart';
import '../domain/staff_invitation.dart';
import '../domain/system_roles.dart';
import '../domain/team_exception.dart';

Stream<List<QuerySnapshot<Map<String, dynamic>>>> _combineActivitySnapshots(
  Stream<QuerySnapshot<Map<String, dynamic>>> first,
  Stream<QuerySnapshot<Map<String, dynamic>>> second,
) {
  late StreamController<List<QuerySnapshot<Map<String, dynamic>>>> controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firstSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? secondSubscription;
  QuerySnapshot<Map<String, dynamic>>? latestFirst;
  QuerySnapshot<Map<String, dynamic>>? latestSecond;

  void emit() {
    final firstValue = latestFirst;
    final secondValue = latestSecond;
    if (firstValue != null && secondValue != null && !controller.isClosed) {
      controller.add(<QuerySnapshot<Map<String, dynamic>>>[
        firstValue,
        secondValue,
      ]);
    }
  }

  controller = StreamController<List<QuerySnapshot<Map<String, dynamic>>>>(
    onListen: () {
      firstSubscription = first.listen((snapshot) {
        latestFirst = snapshot;
        emit();
      }, onError: controller.addError);
      secondSubscription = second.listen((snapshot) {
        latestSecond = snapshot;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    },
  );
  return controller.stream;
}

class TeamRepository {
  TeamRepository({
    FirebaseFirestore? firestore,
    AuthenticatedApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _apiClient =
           apiClient ?? (firestore == null ? AuthenticatedApiClient() : null);

  final FirebaseFirestore _db;
  final AuthenticatedApiClient? _apiClient;

  CollectionReference<Map<String, dynamic>> _members(String businessId) =>
      _db.collection('businesses').doc(businessId).collection('members');

  CollectionReference<Map<String, dynamic>> _branches(String businessId) =>
      _db.collection('businesses').doc(businessId).collection('branches');

  CollectionReference<Map<String, dynamic>> _roles(String businessId) =>
      _db.collection('businesses').doc(businessId).collection('roles');

  CollectionReference<Map<String, dynamic>> _invitations(String businessId) =>
      _db
          .collection('businesses')
          .doc(businessId)
          .collection('staff_invitations');

  CollectionReference<Map<String, dynamic>> _activity(String businessId) =>
      _db.collection('businesses').doc(businessId).collection('staff_activity');

  CollectionReference<Map<String, dynamic>> _approvals(String businessId) => _db
      .collection('businesses')
      .doc(businessId)
      .collection('approval_requests');

  DocumentReference<Map<String, dynamic>> _approvalPolicies(
    String businessId,
  ) => _db
      .collection('businesses')
      .doc(businessId)
      .collection('settings')
      .doc('approval_policies');

  // ── Membership ──────────────────────────────────────────────

  Stream<BusinessMembership?> watchMembership({
    required String businessId,
    required String uid,
  }) {
    if (businessId.isEmpty || uid.isEmpty) {
      return Stream.value(null);
    }
    return _members(businessId).doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return BusinessMembership.fromMap(uid, businessId, snap.data()!);
    });
  }

  Future<BusinessMembership?> getMembership({
    required String businessId,
    required String uid,
  }) async {
    if (businessId.isEmpty || uid.isEmpty) return null;
    final snap = await _members(businessId).doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return BusinessMembership.fromMap(uid, businessId, snap.data()!);
  }

  Stream<List<BusinessMembership>> watchMembers(String businessId) {
    if (businessId.isEmpty) return Stream.value(const []);
    return _members(businessId).snapshots().map((snap) {
      return snap.docs
          .map((d) => BusinessMembership.fromMap(d.id, businessId, d.data()))
          .toList(growable: false);
    });
  }

  Future<int> countActiveOwners(String businessId) async {
    final snap = await _members(
      businessId,
    ).where('status', isEqualTo: MemberStatus.active.storedValue).get();
    var count = 0;
    for (final doc in snap.docs) {
      final m = BusinessMembership.fromMap(doc.id, businessId, doc.data());
      if (m.isOwner) count++;
    }
    // Fallback: business.ownerId when members lack isOwner on legacy docs.
    if (count == 0) {
      final biz = await _db.collection('businesses').doc(businessId).get();
      final ownerId = biz.data()?['ownerId'] as String?;
      if (ownerId != null && ownerId.isNotEmpty) {
        final ownerMember = snap.docs.where((d) => d.id == ownerId);
        if (ownerMember.isNotEmpty) return 1;
      }
    }
    return count;
  }

  Future<void> ensureDefaultRoles(
    String businessId, {
    String? createdBy,
  }) async {
    if (businessId.isEmpty) return;
    final existing = await _roles(businessId).limit(1).get();
    if (existing.docs.isEmpty) {
      final batch = _db.batch();
      for (final role in SystemRoles.buildDefaults(businessId)) {
        batch.set(_roles(businessId).doc(role.id), {
          ...role.toMap(),
          'createdBy': createdBy,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Upgrade legacy thin owner membership docs once.
    if (createdBy != null && createdBy.isNotEmpty) {
      final biz = await _db.collection('businesses').doc(businessId).get();
      final ownerId = biz.data()?['ownerId'] as String?;
      if (ownerId == createdBy) {
        final memberRef = _members(businessId).doc(ownerId);
        final memberSnap = await memberRef.get();
        if (memberSnap.exists) {
          final data = memberSnap.data() ?? {};
          if (data['roleId'] == null || data['permissions'] == null) {
            await memberRef.set({
              'uid': ownerId,
              'userId': ownerId,
              'businessId': businessId,
              'roleId': SystemRoleIds.owner,
              'role': SystemRoleIds.owner,
              'roleName': 'Owner',
              'isOwner': true,
              'status': MemberStatus.active.storedValue,
              'permissions': AppPermission.values.map((p) => p.code).toList(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    }
  }

  Stream<List<RoleDefinition>> watchRoles(String businessId) {
    if (businessId.isEmpty) return Stream.value(const []);
    return _roles(businessId).snapshots().map((snap) {
      final roles = snap.docs
          .map((d) => RoleDefinition.fromMap(d.id, businessId, d.data()))
          .toList();
      roles.sort((a, b) {
        if (a.isSystemRole != b.isSystemRole) {
          return a.isSystemRole ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
      return roles;
    });
  }

  Future<RoleDefinition?> getRole(String businessId, String roleId) async {
    final snap = await _roles(businessId).doc(roleId).get();
    if (!snap.exists || snap.data() == null) {
      // Fall back to in-memory system role.
      if (SystemRoleIds.isSystem(roleId)) {
        return SystemRoles.buildDefaults(
          businessId,
        ).firstWhere((r) => r.id == roleId);
      }
      return null;
    }
    return RoleDefinition.fromMap(roleId, businessId, snap.data()!);
  }

  Future<String> createCustomRole({
    required String businessId,
    required String name,
    required String description,
    required Set<AppPermission> permissions,
    required String createdBy,
  }) async {
    final ref = _roles(businessId).doc();
    final role = RoleDefinition(
      id: ref.id,
      businessId: businessId,
      name: name.trim(),
      description: description.trim(),
      permissions: permissions,
      isSystemRole: false,
      isEditable: true,
      isActive: true,
      createdBy: createdBy,
    );
    await ref.set({
      ...role.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateCustomRole({
    required String businessId,
    required String roleId,
    required String name,
    required String description,
    required Set<AppPermission> permissions,
    required String updatedBy,
  }) async {
    final existing = await getRole(businessId, roleId);
    if (existing == null) throw TeamException.unknown;
    if (existing.isSystemRole) {
      throw const TeamException('Built-in roles cannot be edited.');
    }
    await _roles(businessId).doc(roleId).update({
      'name': name.trim(),
      'description': description.trim(),
      'permissions': permissions.map((p) => p.code).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  Future<void> disableCustomRole({
    required String businessId,
    required String roleId,
    required String updatedBy,
  }) async {
    final existing = await getRole(businessId, roleId);
    if (existing == null) throw TeamException.unknown;
    if (existing.isSystemRole) {
      throw const TeamException('Built-in roles cannot be deleted.');
    }
    final assigned = await _members(businessId)
        .where('roleId', isEqualTo: roleId)
        .where('status', isEqualTo: MemberStatus.active.storedValue)
        .limit(1)
        .get();
    if (assigned.docs.isNotEmpty) {
      throw const TeamException(
        'This role is assigned to active staff. Reassign them first.',
      );
    }
    await _roles(businessId).doc(roleId).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  // ── Invitations ─────────────────────────────────────────────

  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String? normalizeEmail(String? email) {
    final v = email?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static String? normalizePhone(String? phone) {
    if (phone == null) return null;
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;
    return digits;
  }

  Future<StaffInvitation> createInvitation({
    required String businessId,
    required String businessName,
    required String invitedBy,
    required String invitedByName,
    required String roleId,
    required String roleName,
    required Set<AppPermission> permissions,
    String? email,
    String? phone,
    String? displayName,
    String? message,
    Duration expiresIn = const Duration(days: 7),
  }) async {
    final normalizedEmail = normalizeEmail(email);
    final normalizedPhone = normalizePhone(phone);
    if ((normalizedEmail == null || normalizedEmail.isEmpty) &&
        (normalizedPhone == null || normalizedPhone.isEmpty)) {
      throw const TeamException('Enter an email or phone number.');
    }

    // Block duplicate pending invitation.
    QuerySnapshot<Map<String, dynamic>> pending;
    if (normalizedEmail != null) {
      pending = await _invitations(businessId)
          .where('normalizedEmail', isEqualTo: normalizedEmail)
          .where('status', isEqualTo: InvitationStatus.pending.storedValue)
          .limit(1)
          .get();
      if (pending.docs.isNotEmpty) {
        throw const TeamException(
          'A pending invitation already exists for this email.',
        );
      }
    }

    final apiClient = _apiClient;
    if (apiClient != null) {
      try {
        final response = await apiClient.postJson(
          '/api/team/invite',
          body: {
            'businessId': businessId,
            'email': ?normalizedEmail,
            'phone': ?normalizedPhone,
            if (displayName?.trim().isNotEmpty == true)
              'displayName': displayName!.trim(),
            'roleId': roleId,
            'roleName': roleName,
            'permissions': permissions.map((item) => item.code).toList(),
            if (message?.trim().isNotEmpty == true) 'message': message!.trim(),
            'expiresInDays': expiresIn.inDays.clamp(1, 30),
          },
        );
        return StaffInvitation(
          id: response['invitationId'] as String,
          businessId: businessId,
          businessName: businessName,
          email: email?.trim(),
          normalizedEmail: normalizedEmail,
          phone: phone?.trim(),
          normalizedPhone: normalizedPhone,
          displayName: displayName?.trim(),
          roleId: roleId,
          roleName: roleName,
          permissionsSnapshot: permissions,
          status: InvitationStatus.pending,
          invitedBy: invitedBy,
          invitedByName: invitedByName,
          inviteCode: response['inviteCode'] as String,
          expiresAt: DateTime.parse(response['expiresAt'] as String),
          message: message?.trim(),
        );
      } on ApiException catch (error) {
        throw TeamException(error.message, code: error.code);
      }
    }

    // Explicit Firestore injection is retained for repository unit tests only.
    final ref = _invitations(businessId).doc();
    final invitation = StaffInvitation(
      id: ref.id,
      businessId: businessId,
      businessName: businessName,
      email: email?.trim(),
      normalizedEmail: normalizedEmail,
      phone: phone?.trim(),
      normalizedPhone: normalizedPhone,
      displayName: displayName?.trim(),
      roleId: roleId,
      roleName: roleName,
      permissionsSnapshot: permissions,
      status: InvitationStatus.pending,
      invitedBy: invitedBy,
      invitedByName: invitedByName,
      inviteCode: generateInviteCode(),
      expiresAt: DateTime.now().add(expiresIn),
      message: message?.trim(),
    );
    await ref.set(invitation.toCreateMap());

    // If the invitee already has a SabiBom account, notify them in-app.
    if (normalizedEmail != null) {
      try {
        final users = await _db
            .collection('users')
            .where('email', isEqualTo: normalizedEmail)
            .limit(1)
            .get();
        if (users.docs.isNotEmpty) {
          final inviteeUid = users.docs.first.id;
          await _db
              .collection('users')
              .doc(inviteeUid)
              .collection('notifications')
              .doc()
              .set({
                'type': 'invitation_received',
                'title': 'Team invitation',
                'body': 'You were invited to join $businessName as $roleName.',
                'read': false,
                'businessId': businessId,
                'entityType': 'invitation',
                'entityId': ref.id,
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
      } catch (_) {
        // Notification is best-effort; invitation still succeeds.
      }
    }

    return invitation;
  }

  Stream<List<StaffInvitation>> watchInvitations(String businessId) {
    if (businessId.isEmpty) return Stream.value(const []);
    return _invitations(businessId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => StaffInvitation.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<StaffInvitation?> getInvitation({
    required String businessId,
    required String invitationId,
  }) async {
    final snap = await _invitations(businessId).doc(invitationId).get();
    if (!snap.exists || snap.data() == null) return null;
    return StaffInvitation.fromMap(invitationId, snap.data()!);
  }

  Future<StaffInvitation?> findInvitationByCode(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    // Collection group query for invite codes.
    final snap = await _db
        .collectionGroup('staff_invitations')
        .where('inviteCode', isEqualTo: code)
        .where('status', isEqualTo: InvitationStatus.pending.storedValue)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return StaffInvitation.fromMap(doc.id, doc.data());
  }

  Future<StaffInvitation?> findInvitationByDocumentId(
    String invitationId,
  ) async {
    final id = invitationId.trim();
    if (id.isEmpty) return null;
    final snap = await _db
        .collectionGroup('staff_invitations')
        .where('id', isEqualTo: id)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return StaffInvitation.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  Future<BusinessMembership> acceptInvitation({
    required StaffInvitation invitation,
    required String uid,
    required String? userEmail,
    required String? userPhone,
    required String? displayName,
    required String? photoUrl,
  }) async {
    if (!invitation.isAcceptable) {
      if (invitation.isExpired) throw TeamException.invitationExpired;
      throw TeamException.invitationUsed;
    }

    final emailMatch =
        invitation.normalizedEmail == null ||
        invitation.normalizedEmail == normalizeEmail(userEmail);
    final phoneMatch =
        invitation.normalizedPhone == null ||
        invitation.normalizedPhone == normalizePhone(userPhone);
    if (!emailMatch && !phoneMatch) {
      // If invitation has email, require email match; else phone.
      if (invitation.normalizedEmail != null) {
        throw const TeamException(
          'Sign in with the email address that was invited.',
        );
      }
      if (invitation.normalizedPhone != null) {
        throw const TeamException(
          'Sign in with the phone number that was invited.',
        );
      }
    }

    final memberRef = _members(invitation.businessId).doc(uid);
    final inviteRef = _invitations(invitation.businessId).doc(invitation.id);

    return _db.runTransaction((tx) async {
      final existing = await tx.get(memberRef);
      if (existing.exists) {
        final current = BusinessMembership.fromMap(
          uid,
          invitation.businessId,
          existing.data()!,
        );
        if (current.status == MemberStatus.active) {
          throw TeamException.existingMember;
        }
      }

      final inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) throw TeamException.invitationUsed;
      final live = StaffInvitation.fromMap(invitation.id, inviteSnap.data()!);
      if (!live.isAcceptable) {
        if (live.isExpired) throw TeamException.invitationExpired;
        throw TeamException.invitationUsed;
      }

      final membership = BusinessMembership(
        uid: uid,
        businessId: invitation.businessId,
        displayName: displayName ?? invitation.displayName,
        email: userEmail,
        phone: userPhone,
        photoUrl: photoUrl,
        roleId: invitation.roleId,
        roleName: invitation.roleName,
        permissions: invitation.permissionsSnapshot.isNotEmpty
            ? invitation.permissionsSnapshot
            : SystemRoles.defaultPermissionsFor(invitation.roleId),
        status: MemberStatus.active,
        isOwner: false,
        invitedBy: invitation.invitedBy,
        invitationId: invitation.id,
      );

      tx.set(memberRef, membership.toMap(forCreate: true));
      tx.update(inviteRef, {
        'status': InvitationStatus.accepted.storedValue,
        'acceptedBy': uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Set active business for invitee if empty.
      final userRef = _db.collection('users').doc(uid);
      tx.set(userRef, {
        'activeBusinessId': invitation.businessId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return membership;
    });
  }

  Future<void> cancelInvitation({
    required String businessId,
    required String invitationId,
    required String cancelledBy,
  }) async {
    await _invitations(businessId).doc(invitationId).update({
      'status': InvitationStatus.cancelled.storedValue,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': cancelledBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Staff lifecycle ─────────────────────────────────────────

  Future<void> updateMemberRole({
    required String businessId,
    required String targetUid,
    required String roleId,
    required String roleName,
    required Set<AppPermission> permissions,
    required String updatedBy,
    required BusinessMembership actor,
  }) async {
    if (roleId == SystemRoleIds.owner && !actor.isOwner) {
      throw const TeamException('Only an owner can assign the owner role.');
    }

    final target = await getMembership(businessId: businessId, uid: targetUid);
    if (target == null) throw TeamException.unknown;

    if (target.isOwner && roleId != SystemRoleIds.owner) {
      final owners = await countActiveOwners(businessId);
      if (owners <= 1) throw TeamException.lastOwner;
    }

    // Managers can only grant permissions they have.
    final grantable = PermissionService.filterGrantable(actor, permissions);
    if (!actor.isOwner && grantable.length != permissions.length) {
      throw const TeamException(
        'You cannot grant permissions you do not have.',
      );
    }

    await _members(businessId).doc(targetUid).update({
      'roleId': roleId,
      'role': roleId,
      'roleName': roleName,
      'permissions': grantable.map((p) => p.code).toList(),
      'permissionOverrides': <String>[],
      'isOwner': roleId == SystemRoleIds.owner,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  Future<void> updateMemberPermissions({
    required String businessId,
    required String targetUid,
    required Set<AppPermission> permissions,
    required String updatedBy,
    required BusinessMembership actor,
  }) async {
    if (targetUid == actor.uid) {
      throw const TeamException('You cannot edit your own permissions.');
    }
    final target = await getMembership(businessId: businessId, uid: targetUid);
    if (target == null) throw TeamException.unknown;
    if (target.isOwner) {
      throw const TeamException(
        'Owner permissions cannot be changed this way.',
      );
    }

    final grantable = PermissionService.filterGrantable(actor, permissions);
    await _members(businessId).doc(targetUid).update({
      'permissions': grantable.map((p) => p.code).toList(),
      'permissionOverrides': grantable.map((p) => p.code).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  Future<void> updateMemberBranchAccess({
    required String businessId,
    required String targetUid,
    required Set<String> assignedBranchIds,
    required bool allBranchesAccess,
    required String? defaultBranchId,
    required String updatedBy,
    required BusinessMembership actor,
  }) async {
    if (targetUid == actor.uid) {
      throw const TeamException('You cannot change your own branch access.');
    }
    final target = await getMembership(businessId: businessId, uid: targetUid);
    if (target == null) throw TeamException.unknown;
    if (target.isOwner) {
      throw const TeamException('Owner branch access cannot be restricted.');
    }
    if (target.permissionDenials.contains(AppPermission.viewBranch)) {
      throw const TeamException(
        'Remove the View Branch denial before assigning this staff member.',
      );
    }
    if (!actor.hasPermission(AppPermission.assignStaffToBranches) &&
        !actor.isOwner) {
      throw const TeamException(
        'You do not have permission to manage branch assignments.',
      );
    }

    final normalizedAssigned = assignedBranchIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedDefault = defaultBranchId?.trim();

    final branches = actor.isOwner
        ? (await _branches(businessId).get()).docs
              .map(
                (doc) => BusinessBranch.fromMap(doc.data(), doc.id, businessId),
              )
              .toList(growable: false)
        : (await Future.wait(
                actor.assignedBranchIds.map(
                  (branchId) => _branches(businessId).doc(branchId).get(),
                ),
              ))
              .where((doc) => doc.exists && doc.data() != null)
              .map(
                (doc) =>
                    BusinessBranch.fromMap(doc.data()!, doc.id, businessId),
              )
              .toList(growable: false);
    final activeBranchIds = branches
        .where((branch) => branch.isActive)
        .map((branch) => branch.branchId)
        .toSet();

    for (final branchId in normalizedAssigned) {
      if (!activeBranchIds.contains(branchId)) {
        throw TeamException(
          'Assigned branch $branchId is missing or inactive.',
        );
      }
      if (!actor.isOwner && !actor.hasBranchAccess(branchId)) {
        throw TeamException('You cannot assign a branch you cannot access.');
      }
    }

    if (normalizedDefault != null && normalizedDefault.isNotEmpty) {
      if (!activeBranchIds.contains(normalizedDefault)) {
        throw const TeamException('Default branch must be active.');
      }
      if (!normalizedAssigned.contains(normalizedDefault)) {
        throw const TeamException(
          'Default branch must be part of assigned branches.',
        );
      }
      if (!actor.isOwner && !actor.hasBranchAccess(normalizedDefault)) {
        throw const TeamException(
          'You cannot set a default branch you cannot access.',
        );
      }
    }

    final added = normalizedAssigned.difference(target.assignedBranchIds);
    final removed = target.assignedBranchIds.difference(normalizedAssigned);
    final batch = _db.batch()
      ..update(_members(businessId).doc(targetUid), {
        'assignedBranchIds': normalizedAssigned.toList(),
        'allBranchesAccess': allBranchesAccess,
        'defaultBranchId':
            (normalizedDefault == null || normalizedDefault.isEmpty)
            ? null
            : normalizedDefault,
        'permissionOverrides': {
          ...target.permissionOverrides,
          AppPermission.viewBranch,
        }.map((permission) => permission.code).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    for (final branchId in added) {
      final ref = _activity(businessId).doc();
      batch.set(
        ref,
        StaffActivity(
          id: ref.id,
          businessId: businessId,
          userId: updatedBy,
          userName: actor.effectiveDisplayName,
          userRole: actor.roleId,
          actionType: StaffActionType.staffBranchAssigned,
          entityType: 'member',
          entityId: targetUid,
          entityLabel: target.effectiveDisplayName,
          description: 'Assigned staff to branch.',
          metadata: {'branchId': branchId},
        ).toCreateMap(),
      );
    }
    for (final branchId in removed) {
      final ref = _activity(businessId).doc();
      batch.set(
        ref,
        StaffActivity(
          id: ref.id,
          businessId: businessId,
          userId: updatedBy,
          userName: actor.effectiveDisplayName,
          userRole: actor.roleId,
          actionType: StaffActionType.staffBranchRemoved,
          entityType: 'member',
          entityId: targetUid,
          entityLabel: target.effectiveDisplayName,
          description: 'Removed staff from branch.',
          metadata: {'branchId': branchId},
        ).toCreateMap(),
      );
    }
    await batch.commit();
  }

  Future<void> disableMember({
    required String businessId,
    required String targetUid,
    required String disabledBy,
    String? reason,
  }) async {
    final target = await getMembership(businessId: businessId, uid: targetUid);
    if (target == null) throw TeamException.unknown;
    if (target.isOwner) {
      final owners = await countActiveOwners(businessId);
      if (owners <= 1) throw TeamException.lastOwner;
    }
    await _members(businessId).doc(targetUid).update({
      'status': MemberStatus.disabled.storedValue,
      'disabledAt': FieldValue.serverTimestamp(),
      'disabledBy': disabledBy,
      'disableReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': disabledBy,
    });
  }

  Future<void> restoreMember({
    required String businessId,
    required String targetUid,
    required String restoredBy,
  }) async {
    await _members(businessId).doc(targetUid).update({
      'status': MemberStatus.active.storedValue,
      'disabledAt': null,
      'disabledBy': null,
      'disableReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': restoredBy,
    });
  }

  Future<void> removeMember({
    required String businessId,
    required String targetUid,
    required String removedBy,
    String? reason,
  }) async {
    final target = await getMembership(businessId: businessId, uid: targetUid);
    if (target == null) throw TeamException.unknown;
    if (target.isOwner) {
      final owners = await countActiveOwners(businessId);
      if (owners <= 1) throw TeamException.lastOwner;
    }
    await _members(businessId).doc(targetUid).update({
      'status': MemberStatus.removed.storedValue,
      'removedAt': FieldValue.serverTimestamp(),
      'removedBy': removedBy,
      'removeReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': removedBy,
    });

    // Clear activeBusinessId if it points here.
    final userRef = _db.collection('users').doc(targetUid);
    final userSnap = await userRef.get();
    if (userSnap.data()?['activeBusinessId'] == businessId) {
      await userRef.set({
        'activeBusinessId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // ── Activity ────────────────────────────────────────────────

  Future<void> logActivity(StaffActivity activity) async {
    try {
      final ref = activity.id.isEmpty
          ? _activity(activity.businessId).doc()
          : _activity(activity.businessId).doc(activity.id);
      await ref.set({...activity.toCreateMap(), 'id': ref.id});
    } catch (e, st) {
      debugPrint('Failed to log staff activity: $e\n$st');
    }
  }

  Stream<List<StaffActivity>> watchActivity(
    String businessId, {
    int limit = 50,
    String? userId,
    StaffActionType? actionType,
    bool sensitiveOnly = false,
  }) {
    if (businessId.isEmpty) return Stream.value(const []);
    final legacy = _activity(
      businessId,
    ).orderBy('createdAt', descending: true).limit(limit).snapshots();
    final operational = _activity(
      businessId,
    ).orderBy('timestamp', descending: true).limit(limit).snapshots();
    return _combineActivitySnapshots(legacy, operational).map((snapshots) {
      final byId = <String, StaffActivity>{};
      for (final snap in snapshots) {
        for (final document in snap.docs) {
          byId[document.id] = StaffActivity.fromMap(
            document.id,
            document.data(),
          );
        }
      }
      var items = byId.values.toList()
        ..sort(
          (left, right) =>
              (right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
        );
      if (userId != null && userId.isNotEmpty) {
        items = items.where((activity) => activity.userId == userId).toList();
      }
      if (actionType != null) {
        items = items
            .where((activity) => activity.actionType == actionType)
            .toList();
      }
      if (sensitiveOnly) {
        items = items.where((a) => a.actionType.isSensitive).toList();
      }
      return items.take(limit).toList(growable: false);
    });
  }

  Future<List<StaffActivity>> fetchActivityPage({
    required String businessId,
    int limit = 40,
    DocumentSnapshot? startAfter,
    String? userId,
  }) async {
    Query<Map<String, dynamic>> q = _activity(
      businessId,
    ).orderBy('createdAt', descending: true);
    if (userId != null && userId.isNotEmpty) {
      q = q.where('userId', isEqualTo: userId);
    }
    q = q.limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final snap = await q.get();
    return snap.docs
        .map((d) => StaffActivity.fromMap(d.id, d.data()))
        .toList(growable: false);
  }

  // ── Approvals ───────────────────────────────────────────────

  Stream<ApprovalPolicies> watchApprovalPolicies(String businessId) {
    if (businessId.isEmpty) {
      return Stream.value(const ApprovalPolicies());
    }
    return _approvalPolicies(businessId).snapshots().map((snap) {
      return ApprovalPolicies.fromMap(snap.data());
    });
  }

  Future<void> saveApprovalPolicies({
    required String businessId,
    required ApprovalPolicies policies,
  }) async {
    await _approvalPolicies(
      businessId,
    ).set(policies.toMap(), SetOptions(merge: true));
  }

  Stream<List<ApprovalRequest>> watchApprovals(
    String businessId, {
    ApprovalStatus? status,
    String? requestedBy,
    int limit = 50,
  }) {
    if (businessId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _approvals(
      businessId,
    ).orderBy('requestedAt', descending: true);
    if (status != null) {
      q = q.where('status', isEqualTo: status.storedValue);
    }
    if (requestedBy != null && requestedBy.isNotEmpty) {
      q = q.where('requestedBy', isEqualTo: requestedBy);
    }
    return q
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ApprovalRequest.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<ApprovalRequest?> getApproval({
    required String businessId,
    required String approvalId,
  }) async {
    final snap = await _approvals(businessId).doc(approvalId).get();
    if (!snap.exists || snap.data() == null) return null;
    return ApprovalRequest.fromMap(approvalId, snap.data()!);
  }

  Future<String> createApprovalRequest(ApprovalRequest request) async {
    final ref = request.id.isEmpty
        ? _approvals(request.businessId).doc()
        : _approvals(request.businessId).doc(request.id);
    await ref.set({...request.toCreateMap(), 'id': ref.id});
    return ref.id;
  }

  Future<void> approveRequest({
    required String businessId,
    required String approvalId,
    required String approvedBy,
    required String approvedByName,
  }) async {
    final ref = _approvals(businessId).doc(approvalId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw TeamException.unknown;
      final live = ApprovalRequest.fromMap(approvalId, snap.data()!);
      if (live.status != ApprovalStatus.pending) {
        throw TeamException.approvalHandled;
      }
      if (live.expiresAt != null && DateTime.now().isAfter(live.expiresAt!)) {
        tx.update(ref, {
          'status': ApprovalStatus.expired.storedValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        throw const TeamException('This approval request has expired.');
      }
      if (live.requestedBy == approvedBy) {
        throw const TeamException('You cannot approve your own request.');
      }
      tx.update(ref, {
        'status': ApprovalStatus.approved.storedValue,
        'approvedBy': approvedBy,
        'approvedByName': approvedByName,
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectRequest({
    required String businessId,
    required String approvalId,
    required String rejectedBy,
    required String rejectedByName,
    required String rejectionReason,
  }) async {
    if (rejectionReason.trim().isEmpty) {
      throw const TeamException('Enter a reason for rejecting this request.');
    }
    final ref = _approvals(businessId).doc(approvalId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw TeamException.unknown;
      final live = ApprovalRequest.fromMap(approvalId, snap.data()!);
      if (live.status != ApprovalStatus.pending) {
        throw TeamException.approvalHandled;
      }
      tx.update(ref, {
        'status': ApprovalStatus.rejected.storedValue,
        'rejectedBy': rejectedBy,
        'rejectedByName': rejectedByName,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': rejectionReason.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelApprovalRequest({
    required String businessId,
    required String approvalId,
    required String cancelledBy,
  }) async {
    final ref = _approvals(businessId).doc(approvalId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw TeamException.unknown;
      final live = ApprovalRequest.fromMap(approvalId, snap.data()!);
      if (live.status != ApprovalStatus.pending) {
        throw TeamException.approvalHandled;
      }
      if (live.requestedBy != cancelledBy) {
        throw TeamException.permissionDenied;
      }
      tx.update(ref, {
        'status': ApprovalStatus.cancelled.storedValue,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
